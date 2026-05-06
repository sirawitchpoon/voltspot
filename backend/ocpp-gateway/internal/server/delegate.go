package server

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"sync"
	"time"

	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/firestore"
	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/ocpp"
	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/pricing"
	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/transactions"
)

// AppDelegate implements server.Delegate by translating OCPP messages
// into Firestore writes + pricing computations. Pure logic — the
// Conn handles all transport.
//
// One AppDelegate is shared by every Conn; per-charger state lives
// in Firestore (or in the active session map below for fast access
// during a session).
type AppDelegate struct {
	Logger        *slog.Logger
	Firestore     *firestore.Writer
	Pricing       PricingProvider
	TxIDs         *transactions.Allocator
	PendingStarts *PendingStarts // app-initiated user linkage; nil ⇒ no linkage

	// activeSessions caches the {transactionId → session info} we need
	// to compute MeterValues cost without a Firestore round-trip on
	// every reading. Bound to the in-memory hub lifetime — on Gateway
	// restart we rehydrate from /sessions where status == "active".
	mu             sync.RWMutex
	activeSessions map[int]*activeSession

	// chargerStations is the {chargePointID → stationId} mapping
	// resolved at BootNotification. Used by StartTransaction /
	// MeterValues / StopTransaction to decide which Firestore station
	// doc to read for tariff. For MVP we treat chargePointID as the
	// stationId — when chargers and stations are 1:1 this is fine;
	// when one station has multiple chargers the registry must
	// translate. Override the resolver via StationResolver.
	StationResolver StationResolver
}

type activeSession struct {
	stationID    string
	connectorID  int
	userID       string // empty for charger-initiated (RFID) sessions
	idTag        string
	meterStartWh int
	tariff       pricing.Tariff
	startedAt    time.Time
}

// PricingProvider returns the tariff for a station + connector.
// Implementations look up the station doc and return its tariff;
// failure to find a tariff is fatal for a session start.
type PricingProvider interface {
	Tariff(ctx context.Context, stationID string) (pricing.Tariff, error)
}

// StationResolver maps a charge point identity to a Firestore
// station ID. The default — return the chargePointID unchanged —
// fits a 1:1 mapping. Override to support shared stations.
type StationResolver func(chargePointID string) string

// NewAppDelegate constructs an AppDelegate with sane defaults.
//
// Pass `pendingStarts` to enable iOS-initiated session linkage; when
// nil, charger-initiated StartTransactions still produce session
// docs but with `userId=""` (RFID flow without our future /idtags
// integration).
func NewAppDelegate(
	logger *slog.Logger,
	fs *firestore.Writer,
	tariffs PricingProvider,
	txIDs *transactions.Allocator,
	pendingStarts *PendingStarts,
) *AppDelegate {
	return &AppDelegate{
		Logger:          logger,
		Firestore:       fs,
		Pricing:         tariffs,
		TxIDs:           txIDs,
		PendingStarts:   pendingStarts,
		activeSessions:  make(map[int]*activeSession),
		StationResolver: defaultStationResolver,
	}
}

func defaultStationResolver(cpID string) string { return cpID }

// ─── Conn lifecycle ──────────────────────────────────────────────────

func (d *AppDelegate) OnConnect(_ context.Context, chargePointID string) {
	d.Logger.Info("charger connected", slog.String("cp", chargePointID))
}

func (d *AppDelegate) OnDisconnect(ctx context.Context, chargePointID string, cause error) {
	d.Logger.Info("charger disconnected",
		slog.String("cp", chargePointID),
		slog.String("cause", causeString(cause)))

	// Find any in-flight sessions for this charger and mark them
	// interrupted so the iOS app stops showing them as active.
	d.mu.Lock()
	var orphaned []int
	for txID, s := range d.activeSessions {
		if s.stationID == d.StationResolver(chargePointID) {
			orphaned = append(orphaned, txID)
		}
	}
	d.mu.Unlock()

	for _, txID := range orphaned {
		d.markSessionInterrupted(ctx, txID, "charger disconnected")
	}
}

// ─── Inbound Calls ───────────────────────────────────────────────────

func (d *AppDelegate) OnCall(
	ctx context.Context,
	chargePointID string,
	action ocpp.Action,
	payload json.RawMessage,
) (any, *CallError) {
	switch action {
	case ocpp.ActionBootNotification:
		return d.onBoot(ctx, chargePointID, payload)
	case ocpp.ActionHeartbeat:
		return d.onHeartbeat(ctx, chargePointID, payload)
	case ocpp.ActionStatusNotification:
		return d.onStatusNotification(ctx, chargePointID, payload)
	case ocpp.ActionAuthorize:
		return d.onAuthorize(ctx, chargePointID, payload)
	case ocpp.ActionStartTransaction:
		return d.onStartTransaction(ctx, chargePointID, payload)
	case ocpp.ActionMeterValues:
		return d.onMeterValues(ctx, chargePointID, payload)
	case ocpp.ActionStopTransaction:
		return d.onStopTransaction(ctx, chargePointID, payload)
	case ocpp.ActionDataTransfer:
		return d.onDataTransfer(ctx, chargePointID, payload)
	default:
		return nil, &CallError{
			Code:        ocpp.ErrorNotImplemented,
			Description: "action " + string(action) + " not implemented by gateway",
		}
	}
}

func (d *AppDelegate) onBoot(ctx context.Context, cpID string, raw json.RawMessage) (any, *CallError) {
	var req ocpp.BootNotificationRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		return nil, malformed("BootNotification", err)
	}
	if req.ChargePointVendor == "" || req.ChargePointModel == "" {
		return nil, &CallError{
			Code:        ocpp.ErrorPropertyConstraintViolation,
			Description: "chargePointVendor and chargePointModel are required",
		}
	}

	d.Logger.Info("boot",
		slog.String("cp", cpID),
		slog.String("vendor", req.ChargePointVendor),
		slog.String("model", req.ChargePointModel),
		slog.String("firmware", deref(req.FirmwareVersion)))

	// Mark the connector-zero "whole charger" as Available so the
	// iOS app's connector_status listener reflects an online charger
	// even before the first per-connector StatusNotification arrives.
	stationID := d.StationResolver(cpID)
	_ = d.Firestore.UpsertConnectorStatus(ctx, firestore.ConnectorStatus{
		StationID:   stationID,
		ConnectorID: 0,
		Status:      string(ocpp.StatusAvailable),
		ErrorCode:   string(ocpp.ErrCodeNoError),
		LastUpdated: time.Now(),
	})

	return ocpp.BootNotificationResponse{
		Status:      ocpp.RegistrationAccepted,
		CurrentTime: ocpp.Now(),
		Interval:    ocpp.HeartbeatIntervalSeconds,
	}, nil
}

func (d *AppDelegate) onHeartbeat(_ context.Context, _ string, _ json.RawMessage) (any, *CallError) {
	return ocpp.HeartbeatResponse{CurrentTime: ocpp.Now()}, nil
}

func (d *AppDelegate) onStatusNotification(ctx context.Context, cpID string, raw json.RawMessage) (any, *CallError) {
	var req ocpp.StatusNotificationRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		return nil, malformed("StatusNotification", err)
	}

	status := req.Status
	if !status.IsKnown() {
		// Unknown status from the charger — coerce to Unavailable
		// rather than reflect a value the iOS rendering layer can't
		// handle. Logged so the operator can spot misbehaving firmware.
		d.Logger.Warn("unknown status from charger",
			slog.String("cp", cpID),
			slog.String("raw_status", string(status)))
		status = ocpp.StatusUnavailable
	}

	stationID := d.StationResolver(cpID)
	cs := firestore.ConnectorStatus{
		StationID:   stationID,
		ConnectorID: req.ConnectorID,
		Status:      string(status),
		ErrorCode:   string(req.ErrorCode),
		LastUpdated: time.Now(),
	}
	if req.Info != nil {
		cs.Info = *req.Info
	}

	if err := d.Firestore.UpsertConnectorStatus(ctx, cs); err != nil {
		d.Logger.Error("upsert connector status",
			slog.String("cp", cpID),
			slog.Int("connector", req.ConnectorID),
			slog.String("err", err.Error()))
		return nil, &CallError{
			Code:        ocpp.ErrorInternalError,
			Description: "failed to persist status",
		}
	}

	return ocpp.StatusNotificationResponse{}, nil
}

func (d *AppDelegate) onAuthorize(_ context.Context, cpID string, raw json.RawMessage) (any, *CallError) {
	var req ocpp.AuthorizeRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		return nil, malformed("Authorize", err)
	}

	// Authorize MVP policy: any non-empty idTag is accepted. The full
	// PDPA-compliant flow (look up /idtags/{idTag} → check status +
	// expiry + concurrentTx) lands in a follow-up. Logged so we can
	// see who's authorising while the policy isn't enforced.
	status := ocpp.AuthAccepted
	if strings.TrimSpace(req.IDTag) == "" {
		status = ocpp.AuthInvalid
	}

	d.Logger.Info("authorize",
		slog.String("cp", cpID),
		slog.String("idTag", redactIDTag(req.IDTag)),
		slog.String("decision", string(status)))

	return ocpp.AuthorizeResponse{
		IDTagInfo: ocpp.IDTagInfo{Status: status},
	}, nil
}

func (d *AppDelegate) onStartTransaction(ctx context.Context, cpID string, raw json.RawMessage) (any, *CallError) {
	var req ocpp.StartTransactionRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		return nil, malformed("StartTransaction", err)
	}

	stationID := d.StationResolver(cpID)
	tariff, err := d.Pricing.Tariff(ctx, stationID)
	if err != nil {
		// No tariff means we can't bill the session. Reject so the
		// charger doesn't begin energy delivery.
		d.Logger.Error("tariff lookup",
			slog.String("station", stationID),
			slog.String("err", err.Error()))
		return ocpp.StartTransactionResponse{
			IDTagInfo: ocpp.IDTagInfo{Status: ocpp.AuthInvalid},
		}, nil
	}

	txID := d.TxIDs.Next()
	now := req.Timestamp.Time
	if now.IsZero() {
		now = time.Now().UTC()
	}

	// If the iOS app initiated this session via /api/.../remote-start,
	// the REST handler stashed a pending entry keyed off the idTag we
	// passed to the charger. Claim it now to stamp the originating
	// Firebase uid onto the session doc — that's what makes the user's
	// charging history populate.
	var userID string
	if d.PendingStarts != nil {
		if claim := d.PendingStarts.Claim(req.IDTag); claim != nil {
			userID = claim.UserID
		}
	}

	if err := d.Firestore.SessionStart(ctx, firestore.SessionStart{
		TransactionID: txID,
		UserID:        userID, // empty for charger-initiated (RFID) flow
		StationID:     stationID,
		ConnectorID:   req.ConnectorID,
		IDTag:         req.IDTag,
		StartTime:     now,
		MeterStartWh:  req.MeterStart,
	}); err != nil {
		d.Logger.Error("session start write",
			slog.Int("tx", txID),
			slog.String("err", err.Error()))
		return ocpp.StartTransactionResponse{
			IDTagInfo: ocpp.IDTagInfo{Status: ocpp.AuthInvalid},
		}, nil
	}

	d.mu.Lock()
	d.activeSessions[txID] = &activeSession{
		stationID:    stationID,
		connectorID:  req.ConnectorID,
		userID:       userID,
		idTag:        req.IDTag,
		meterStartWh: req.MeterStart,
		tariff:       tariff,
		startedAt:    now,
	}
	d.mu.Unlock()

	// Mirror the active transaction id onto the connector_status doc
	// so the partner UI can surface "in use" without joining tables.
	_ = d.Firestore.UpsertConnectorStatus(ctx, firestore.ConnectorStatus{
		StationID:           stationID,
		ConnectorID:         req.ConnectorID,
		Status:              string(ocpp.StatusCharging),
		ErrorCode:           string(ocpp.ErrCodeNoError),
		LastUpdated:         time.Now(),
		ActiveTransactionID: &txID,
	})

	d.Logger.Info("transaction start",
		slog.Int("tx", txID),
		slog.String("station", stationID),
		slog.Int("connector", req.ConnectorID))

	return ocpp.StartTransactionResponse{
		IDTagInfo:     ocpp.IDTagInfo{Status: ocpp.AuthAccepted},
		TransactionID: txID,
	}, nil
}

func (d *AppDelegate) onMeterValues(ctx context.Context, cpID string, raw json.RawMessage) (any, *CallError) {
	var req ocpp.MeterValuesRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		return nil, malformed("MeterValues", err)
	}
	// MeterValues without an active transaction is informational — log
	// and ack so the charger doesn't retry.
	if req.TransactionID == nil {
		return ocpp.MeterValuesResponse{}, nil
	}
	txID := *req.TransactionID

	d.mu.RLock()
	session, ok := d.activeSessions[txID]
	d.mu.RUnlock()
	if !ok {
		// Probably a Gateway restart — no in-memory state. ACK so the
		// charger doesn't spam, and the next StopTransaction will
		// finalize the session record using its own meterStop value.
		d.Logger.Warn("MeterValues for unknown transaction",
			slog.String("cp", cpID),
			slog.Int("tx", txID))
		return ocpp.MeterValuesResponse{}, nil
	}

	// Find the most recent Energy.Active.Import.Register sample. OCPP
	// allows several measurands per MeterValue; we only price on
	// energy delivered. Take the max value we observe so out-of-order
	// samples don't drop our cost.
	latestWh := session.meterStartWh
	for _, mv := range req.MeterValue {
		for _, sample := range mv.SampledValue {
			if sample.Measurand == nil ||
				*sample.Measurand == "Energy.Active.Import.Register" {
				if v := parseWh(sample.Value, sample.Unit); v > latestWh {
					latestWh = v
				}
			}
		}
	}
	kWh, err := pricing.EnergyKWh(session.meterStartWh, latestWh)
	if err != nil {
		d.Logger.Warn("meter rolled backwards",
			slog.Int("tx", txID),
			slog.Int("start", session.meterStartWh),
			slog.Int("latest", latestWh))
		return ocpp.MeterValuesResponse{}, nil
	}
	cost, err := session.tariff.SessionCost(kWh)
	if err != nil {
		d.Logger.Warn("session cost calc",
			slog.Int("tx", txID),
			slog.Float64("kWh", kWh),
			slog.String("err", err.Error()))
		return ocpp.MeterValuesResponse{}, nil
	}

	if err := d.Firestore.SessionMeter(ctx, firestore.SessionMeter{
		TransactionID: txID,
		EnergyKWh:     kWh,
		CostSatang:    cost,
		UpdatedAt:     time.Now(),
	}); err != nil {
		d.Logger.Error("session meter write",
			slog.Int("tx", txID),
			slog.String("err", err.Error()))
	}
	return ocpp.MeterValuesResponse{}, nil
}

func (d *AppDelegate) onStopTransaction(ctx context.Context, cpID string, raw json.RawMessage) (any, *CallError) {
	var req ocpp.StopTransactionRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		return nil, malformed("StopTransaction", err)
	}

	d.mu.Lock()
	session, ok := d.activeSessions[req.TransactionID]
	if ok {
		delete(d.activeSessions, req.TransactionID)
	}
	d.mu.Unlock()

	endTime := req.Timestamp.Time
	if endTime.IsZero() {
		endTime = time.Now().UTC()
	}

	var (
		kWh       float64
		costS     int64
		stopReason string
	)
	if req.Reason != nil {
		stopReason = string(*req.Reason)
	}

	if ok {
		var err error
		kWh, err = pricing.EnergyKWh(session.meterStartWh, req.MeterStop)
		if err != nil {
			kWh = 0
		}
		costS, _ = session.tariff.SessionCost(kWh)
	}

	if err := d.Firestore.SessionStop(ctx, firestore.SessionStop{
		TransactionID: req.TransactionID,
		EndTime:       endTime,
		MeterStopWh:   req.MeterStop,
		EnergyKWh:     kWh,
		CostSatang:    costS,
		Reason:        stopReason,
		Status:        "completed",
	}); err != nil {
		d.Logger.Error("session stop write",
			slog.Int("tx", req.TransactionID),
			slog.String("err", err.Error()))
	}

	if ok {
		_ = d.Firestore.UpsertConnectorStatus(ctx, firestore.ConnectorStatus{
			StationID:   session.stationID,
			ConnectorID: session.connectorID,
			Status:      string(ocpp.StatusFinishing),
			ErrorCode:   string(ocpp.ErrCodeNoError),
			LastUpdated: time.Now(),
			// ActiveTransactionID nil → Firestore field is removed.
		})
	}

	d.Logger.Info("transaction stop",
		slog.Int("tx", req.TransactionID),
		slog.String("reason", stopReason),
		slog.Float64("kWh", kWh),
		slog.Int64("satang", costS))

	return ocpp.StopTransactionResponse{
		IDTagInfo: &ocpp.IDTagInfo{Status: ocpp.AuthAccepted},
	}, nil
}

func (d *AppDelegate) onDataTransfer(_ context.Context, cpID string, raw json.RawMessage) (any, *CallError) {
	var req ocpp.DataTransferRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		return nil, malformed("DataTransfer", err)
	}
	d.Logger.Info("dataTransfer (vendor extension)",
		slog.String("cp", cpID),
		slog.String("vendor", req.VendorID))

	// MVP: no vendor extensions registered. Spec-compliant rejection.
	return ocpp.DataTransferResponse{Status: ocpp.DataTransferUnknownVendorID}, nil
}

// markSessionInterrupted finalises a session that was active when the
// charger disconnected without sending StopTransaction. Best-effort —
// errors are logged; the doc is left in `active` state if the write
// fails so a retry on Gateway restart can pick it up.
func (d *AppDelegate) markSessionInterrupted(ctx context.Context, txID int, reason string) {
	d.mu.Lock()
	session, ok := d.activeSessions[txID]
	if ok {
		delete(d.activeSessions, txID)
	}
	d.mu.Unlock()

	stop := firestore.SessionStop{
		TransactionID: txID,
		EndTime:       time.Now(),
		Status:        "interrupted",
		Reason:        reason,
	}
	if ok {
		// Best estimate: keep the kWh + cost as last known. Without a
		// final meterStop reading we can't update them — leave fields
		// untouched (omit from the SessionStop write).
		_ = session
	}
	if err := d.Firestore.SessionStop(ctx, stop); err != nil {
		d.Logger.Error("mark session interrupted",
			slog.Int("tx", txID),
			slog.String("err", err.Error()))
	}
}

// ─── helpers ─────────────────────────────────────────────────────────

func malformed(action string, err error) *CallError {
	return &CallError{
		Code:        ocpp.ErrorFormationViolation,
		Description: action + " payload malformed: " + err.Error(),
	}
}

// parseWh converts an OCPP SampledValue into Wh, doing a best-effort
// unit conversion when the charger reports kWh instead of Wh.
func parseWh(value string, unit *string) int {
	if value == "" {
		return 0
	}
	// OCPP allows fractional values as strings. Use float64 then cast.
	var f float64
	_, err := fmtScanFloat(value, &f)
	if err != nil {
		return 0
	}
	if unit != nil && strings.EqualFold(*unit, "kWh") {
		f *= 1000
	}
	if f < 0 {
		return 0
	}
	return int(f)
}

// fmtScanFloat is a tiny wrapper to keep parseWh testable and the
// import list small (avoids strconv just for one call site).
func fmtScanFloat(s string, out *float64) (int, error) {
	// Accept "17500", "17500.0", "17.5e3" — Go's default Sscanf uses
	// strconv.ParseFloat under the hood for %g. We use a manual loop
	// to avoid pulling in fmt's reflection scanner.
	// strconv is in stdlib so import would be fine — using it here:
	return scanFloatStrconv(s, out)
}

// causeString returns a short reason string for logging. Distinguishes
// "client closed cleanly" (info-level) from real errors.
func causeString(err error) string {
	if err == nil {
		return "ok"
	}
	if errors.Is(err, ErrConnectionClosed) {
		return "closed"
	}
	if IsClientGone(err) {
		return "client gone"
	}
	return err.Error()
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// redactIDTag returns a privacy-safe representation of an idTag for
// logs. RFID UIDs can identify a user — we keep the first 4 chars
// + length so a support engineer can confirm "looks right" without
// fully exposing the value.
func redactIDTag(s string) string {
	if len(s) <= 4 {
		return strings.Repeat("*", len(s))
	}
	return s[:4] + strings.Repeat("*", len(s)-4)
}
