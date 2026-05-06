package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/auth"
	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/firestore"
	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/ocpp"
)

// RESTHandler exposes the consumer-side HTTP API the iOS app uses to
// kick off remote start/stop operations. Auth is provided by the
// auth.Middleware — handlers here trust ctx contains a verified User.
type RESTHandler struct {
	Hub       *Hub
	Logger    *slog.Logger
	Firestore *firestore.Writer

	// CallTimeout caps how long the REST handler waits for the
	// charger's reply to a CSMS-initiated Call. Independent of the
	// per-Conn timeout because remote operations are interactive
	// (user just tapped a button) — 10s gives the charger time to
	// react without making the user think the app froze.
	CallTimeout time.Duration
}

// Routes wires the handler into a chi-style mux. Returns the
// http.Handler so callers can wrap it in middleware (auth, recovery,
// CORS) before mounting.
func (h *RESTHandler) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /api/stations/{stationId}/connectors/{connectorId}/remote-start", h.remoteStart)
	mux.HandleFunc("POST /api/sessions/{transactionId}/remote-stop", h.remoteStop)
	return mux
}

// remoteStartRequest is the body the iOS app POSTs. idTag identifies
// the user side of the Authorize flow — for MVP we set it from the
// authenticated uid so the Gateway can correlate sessions to users
// without integrating an RFID layer.
type remoteStartRequest struct {
	IDTag string `json:"idTag"` // optional; defaults to user.UID
}

func (h *RESTHandler) remoteStart(w http.ResponseWriter, r *http.Request) {
	user, ok := auth.FromContext(r.Context())
	if !ok {
		// Should never happen — auth middleware guarantees presence.
		writeJSONError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}

	stationID := r.PathValue("stationId")
	connectorIDStr := r.PathValue("connectorId")
	if stationID == "" || connectorIDStr == "" {
		writeJSONError(w, http.StatusBadRequest, "missing path values")
		return
	}
	connectorID, err := strconv.Atoi(connectorIDStr)
	if err != nil || connectorID < 1 {
		writeJSONError(w, http.StatusBadRequest, "connectorId must be a positive integer")
		return
	}

	var body remoteStartRequest
	if r.ContentLength > 0 {
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&body); err != nil {
			writeJSONError(w, http.StatusBadRequest, "malformed JSON: "+err.Error())
			return
		}
	}
	idTag := strings.TrimSpace(body.IDTag)
	if idTag == "" {
		idTag = user.UID
	}

	conn := h.Hub.Lookup(stationID)
	if conn == nil {
		// Charger isn't online. iOS app shows "charger unavailable".
		writeJSONError(w, http.StatusServiceUnavailable, "charger offline")
		return
	}

	connectorIDPtr := connectorID
	req := ocpp.RemoteStartTransactionRequest{
		ConnectorID: &connectorIDPtr,
		IDTag:       idTag,
	}

	ctx, cancel := contextWithDefaultTimeout(r.Context(), h.CallTimeout)
	defer cancel()

	respRaw, err := conn.Send(ctx, ocpp.ActionRemoteStartTransaction, req)
	if err != nil {
		h.Logger.Warn("remote start failed",
			slog.String("station", stationID),
			slog.Int("connector", connectorID),
			slog.String("err", err.Error()))
		writeRemoteCallError(w, err)
		return
	}

	var resp ocpp.RemoteStartTransactionResponse
	if err := json.Unmarshal(respRaw, &resp); err != nil {
		writeJSONError(w, http.StatusBadGateway, "charger reply malformed")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if resp.Status != ocpp.RemoteAccepted {
		w.WriteHeader(http.StatusConflict)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":  string(resp.Status),
			"message": "charger rejected the request",
		})
		return
	}

	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"status":      string(resp.Status),
		"stationId":   stationID,
		"connectorId": connectorID,
	})
}

func (h *RESTHandler) remoteStop(w http.ResponseWriter, r *http.Request) {
	if _, ok := auth.FromContext(r.Context()); !ok {
		writeJSONError(w, http.StatusUnauthorized, "unauthenticated")
		return
	}

	txIDStr := r.PathValue("transactionId")
	txID, err := strconv.Atoi(txIDStr)
	if err != nil || txID < 1 {
		writeJSONError(w, http.StatusBadRequest, "transactionId must be a positive integer")
		return
	}

	session, err := h.Firestore.SessionByTransactionID(r.Context(), txID)
	if err != nil {
		if errors.Is(err, firestore.ErrSessionNotFound) {
			writeJSONError(w, http.StatusNotFound, "session not found")
			return
		}
		writeJSONError(w, http.StatusInternalServerError, "session lookup failed")
		return
	}
	if session.Status != "active" {
		writeJSONError(w, http.StatusConflict, "session not active (status="+session.Status+")")
		return
	}

	conn := h.Hub.Lookup(session.StationID)
	if conn == nil {
		writeJSONError(w, http.StatusServiceUnavailable, "charger offline")
		return
	}

	req := ocpp.RemoteStopTransactionRequest{TransactionID: txID}
	ctx, cancel := contextWithDefaultTimeout(r.Context(), h.CallTimeout)
	defer cancel()

	respRaw, err := conn.Send(ctx, ocpp.ActionRemoteStopTransaction, req)
	if err != nil {
		h.Logger.Warn("remote stop failed",
			slog.Int("tx", txID),
			slog.String("err", err.Error()))
		writeRemoteCallError(w, err)
		return
	}

	var resp ocpp.RemoteStopTransactionResponse
	if err := json.Unmarshal(respRaw, &resp); err != nil {
		writeJSONError(w, http.StatusBadGateway, "charger reply malformed")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	if resp.Status != ocpp.RemoteAccepted {
		w.WriteHeader(http.StatusConflict)
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":  string(resp.Status),
			"message": "charger rejected the stop request",
		})
		return
	}
	w.WriteHeader(http.StatusAccepted)
	_ = json.NewEncoder(w).Encode(map[string]any{
		"status":        string(resp.Status),
		"transactionId": txID,
	})
}

// writeRemoteCallError translates the typed errors that conn.Send
// surfaces into matching HTTP statuses + a JSON envelope the iOS
// GatewayAPIClient can parse. Anything we don't recognise becomes 502.
func writeRemoteCallError(w http.ResponseWriter, err error) {
	if errors.Is(err, ErrConnectionClosed) {
		writeJSONError(w, http.StatusServiceUnavailable, "charger disconnected")
		return
	}
	if errors.Is(err, ErrCallTimeout) {
		writeJSONError(w, http.StatusGatewayTimeout, "charger did not respond")
		return
	}
	var callErr *CallErrorReceived
	if errors.As(err, &callErr) {
		writeJSONError(w, http.StatusBadGateway, fmt.Sprintf(
			"charger replied with %s: %s",
			callErr.Code, callErr.Description,
		))
		return
	}
	writeJSONError(w, http.StatusBadGateway, "remote call failed")
}

func writeJSONError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": message})
}

// contextWithDefaultTimeout applies a deadline to ctx if one isn't
// already present on the request context. Cloud Run terminates
// requests at 60s anyway, but explicit timeouts produce cleaner error
// messages for the iOS client than a raw socket close.
func contextWithDefaultTimeout(ctx context.Context, fallback time.Duration) (context.Context, context.CancelFunc) {
	if _, ok := ctx.Deadline(); ok {
		return ctx, func() {}
	}
	if fallback <= 0 {
		fallback = 10 * time.Second
	}
	return context.WithDeadline(ctx, time.Now().Add(fallback))
}
