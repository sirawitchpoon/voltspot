// Package firestore writes OCPP-derived state into the Firestore
// collections that the iOS app reads:
//
//   /sessions/{sessionId}                    — charging sessions
//   /connector_status/{stationId}_{connectorId}
//                                            — live connector state
//   /stations/{stationId}                    — read-only here, owned
//                                              by the partner upload flow
//
// Schemas live in deploy/firestore.rules + deploy/firestore.indexes.json
// and must stay in lockstep with what RealStationRepository.swift +
// RealSessionRepository.swift expect.
package firestore

import (
	"context"
	"errors"
	"fmt"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

// Writer is a thin wrapper around the Firestore client that exposes
// only the ops the Gateway performs. Holds no per-request state, so a
// single shared instance is safe for the whole process.
type Writer struct {
	client *firestore.Client
}

// New wraps the given Firestore client. The client must be configured
// for the same project Auth runs in — the iOS app uses the project's
// /users/{uid} docs, and the Gateway writes /sessions and
// /connector_status that reference those same uids.
func New(client *firestore.Client) *Writer {
	return &Writer{client: client}
}

// Station is the subset of /stations/{id} the Gateway reads.
// Tariff fields are integer satang per CLAUDE.md money invariant.
type Station struct {
	ID                string
	PartnerID         string
	PricePerKWhSatang int64
	SessionFeeSatang  int64
}

// Station looks up a station by ID. Returns ErrStationNotFound if the
// document is missing — caller decides whether to reject the
// transaction or fall back to a default tariff.
func (w *Writer) Station(ctx context.Context, stationID string) (*Station, error) {
	snap, err := w.client.Collection("stations").Doc(stationID).Get(ctx)
	if err != nil {
		// Firestore returns a typed NotFound error; we keep the original
		// error chain so callers can use errors.Is for upstream policy.
		return nil, err
	}
	data := snap.Data()
	if data == nil {
		return nil, ErrStationNotFound
	}

	st := &Station{ID: stationID}
	if v, ok := data["partnerId"].(string); ok {
		st.PartnerID = v
	}
	if tariff, ok := data["tariff"].(map[string]any); ok {
		st.PricePerKWhSatang = readInt64(tariff["pricePerKWhSatang"])
		st.SessionFeeSatang = readInt64(tariff["sessionFeeSatang"])
	}
	return st, nil
}

// ErrStationNotFound is returned when /stations/{id} doesn't exist.
var ErrStationNotFound = errors.New("firestore: station not found")

// ConnectorStatus is the document layout for /connector_status/{id}.
// Mirrors the shape the iOS partner-side StatusBadge consumes.
type ConnectorStatus struct {
	StationID            string
	ConnectorID          int
	Status               string
	ErrorCode            string
	Info                 string
	LastUpdated          time.Time
	ActiveTransactionID  *int
}

// UpsertConnectorStatus writes the latest StatusNotification to the
// /connector_status/{stationId}_{connectorId} doc. Idempotent — the
// charger may resend the same status during reconnects.
func (w *Writer) UpsertConnectorStatus(ctx context.Context, s ConnectorStatus) error {
	docID := connectorDocID(s.StationID, s.ConnectorID)
	data := map[string]any{
		"stationId":   s.StationID,
		"connectorId": s.ConnectorID,
		"status":      s.Status,
		"errorCode":   s.ErrorCode,
		"lastUpdated": s.LastUpdated,
	}
	if s.Info != "" {
		data["info"] = s.Info
	}
	if s.ActiveTransactionID != nil {
		data["activeTransactionId"] = *s.ActiveTransactionID
	} else {
		// Use FieldValue.delete() so the field is removed when the
		// session ends instead of being left at a stale value.
		data["activeTransactionId"] = firestore.Delete
	}

	_, err := w.client.Collection("connector_status").Doc(docID).Set(ctx, data, firestore.MergeAll)
	if err != nil {
		return fmt.Errorf("firestore: upsert connector status %s: %w", docID, err)
	}
	return nil
}

// SessionStart writes an initial /sessions/{id} doc when
// StartTransaction is accepted. transactionId is the OCPP id, which
// becomes the document ID — same scheme keeps cross-references easy
// (StopTransaction → look up by same id).
type SessionStart struct {
	TransactionID int
	UserID        string
	StationID     string
	ConnectorID   int
	IDTag         string
	StartTime     time.Time
	MeterStartWh  int
}

func (w *Writer) SessionStart(ctx context.Context, s SessionStart) error {
	docID := sessionDocID(s.TransactionID)
	data := map[string]any{
		"ocppTransactionId": s.TransactionID,
		"userId":            s.UserID,
		"stationId":         s.StationID,
		"connectorId":       s.ConnectorID,
		"idTag":             s.IDTag,
		"startTime":         s.StartTime,
		"meterStartWh":      s.MeterStartWh,
		"energyKWh":         0.0,
		"costSatang":        int64(0),
		"status":            "active",
		"createdAt":         firestore.ServerTimestamp,
	}
	_, err := w.client.Collection("sessions").Doc(docID).Set(ctx, data)
	if err != nil {
		return fmt.Errorf("firestore: session start %s: %w", docID, err)
	}
	return nil
}

// SessionMeter is a periodic update from MeterValues. energyKWh +
// costSatang are computed by the caller (pricing package).
type SessionMeter struct {
	TransactionID int
	EnergyKWh     float64
	CostSatang    int64
	UpdatedAt     time.Time
}

func (w *Writer) SessionMeter(ctx context.Context, m SessionMeter) error {
	docID := sessionDocID(m.TransactionID)
	_, err := w.client.Collection("sessions").Doc(docID).Set(ctx, map[string]any{
		"energyKWh":     m.EnergyKWh,
		"costSatang":    m.CostSatang,
		"meterUpdatedAt": m.UpdatedAt,
	}, firestore.MergeAll)
	if err != nil {
		return fmt.Errorf("firestore: session meter %s: %w", docID, err)
	}
	return nil
}

// SessionStop finalizes the doc when StopTransaction arrives. Status
// is set to either "completed" (clean stop) or "interrupted" (charger
// disconnected without a StopTransaction). Cost is the final amount
// the user is billed.
type SessionStop struct {
	TransactionID int
	EndTime       time.Time
	MeterStopWh   int
	EnergyKWh     float64
	CostSatang    int64
	Reason        string
	Status        string // "completed" or "interrupted"
}

func (w *Writer) SessionStop(ctx context.Context, s SessionStop) error {
	docID := sessionDocID(s.TransactionID)
	data := map[string]any{
		"endTime":     s.EndTime,
		"meterStopWh": s.MeterStopWh,
		"energyKWh":   s.EnergyKWh,
		"costSatang":  s.CostSatang,
		"status":      s.Status,
	}
	if s.Reason != "" {
		data["stopReason"] = s.Reason
	}
	_, err := w.client.Collection("sessions").Doc(docID).Set(ctx, data, firestore.MergeAll)
	if err != nil {
		return fmt.Errorf("firestore: session stop %s: %w", docID, err)
	}
	return nil
}

// SessionByID looks up an active session for RemoteStopTransaction.
type Session struct {
	TransactionID int
	UserID        string
	StationID     string
	ConnectorID   int
	Status        string
}

// SessionByTransactionID returns the session document with the given
// OCPP transactionId. Used by REST handlers that need to map a
// session id back to a charge point + connector to issue a
// RemoteStopTransaction.
func (w *Writer) SessionByTransactionID(ctx context.Context, txID int) (*Session, error) {
	snap, err := w.client.Collection("sessions").Doc(sessionDocID(txID)).Get(ctx)
	if err != nil {
		return nil, err
	}
	data := snap.Data()
	if data == nil {
		return nil, ErrSessionNotFound
	}
	s := &Session{TransactionID: txID}
	if v, ok := data["userId"].(string); ok {
		s.UserID = v
	}
	if v, ok := data["stationId"].(string); ok {
		s.StationID = v
	}
	if v, ok := data["connectorId"].(int64); ok {
		s.ConnectorID = int(v)
	}
	if v, ok := data["status"].(string); ok {
		s.Status = v
	}
	return s, nil
}

// ErrSessionNotFound is returned when /sessions/{id} doesn't exist.
var ErrSessionNotFound = errors.New("firestore: session not found")

// MaxTransactionID scans /sessions for the highest ocppTransactionId
// at startup so a fresh allocator doesn't reuse ids. Returns 0 if
// the collection is empty.
//
// Cost note: this is one full collection read at startup. Acceptable
// during MVP (collection size < 10k). Switch to a dedicated
// /counters/transactions doc with FieldValue.Increment when the
// scan exceeds a few seconds.
func (w *Writer) MaxTransactionID(ctx context.Context) (int64, error) {
	iter := w.client.Collection("sessions").
		OrderBy("ocppTransactionId", firestore.Desc).
		Limit(1).
		Documents(ctx)
	defer iter.Stop()

	snap, err := iter.Next()
	if err != nil {
		if errors.Is(err, iterator.Done) {
			return 0, nil
		}
		return 0, fmt.Errorf("firestore: max transaction id: %w", err)
	}
	if v, ok := snap.Data()["ocppTransactionId"].(int64); ok {
		return v, nil
	}
	return 0, nil
}

// ─── helpers ──────────────────────────────────────────────────────────

func connectorDocID(stationID string, connectorID int) string {
	return fmt.Sprintf("%s_%d", stationID, connectorID)
}

func sessionDocID(txID int) string {
	return fmt.Sprintf("tx-%d", txID)
}

// readInt64 coerces the int / int64 / float64 forms Firestore may
// return into a single int64. Numbers stored from the iOS side land
// as int64, but the seed script + a hand-edit could insert a JSON
// number with a fractional zero, so accept both.
func readInt64(v any) int64 {
	switch n := v.(type) {
	case int64:
		return n
	case int:
		return int64(n)
	case float64:
		return int64(n)
	}
	return 0
}
