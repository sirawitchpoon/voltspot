package server

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/coder/websocket"
	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/ocpp"
)

// WSHandler builds an http.HandlerFunc that upgrades a charger's
// HTTP request into a WebSocket and registers the resulting Conn
// with the hub.
//
// URL pattern: /ocpp/{chargePointID}
//
// The chargePointID is extracted from the path — the iOS-side
// WebSocketManager and most chargers in the wild append the identity
// to the URL rather than passing it as a header.
//
// Handshake checks (in order):
//
//  1. Path must contain a non-empty chargePointID.
//  2. Sec-WebSocket-Protocol must include "ocpp1.6". Other versions
//     (2.0.1, etc.) are rejected with HTTP 400 — caller can adapt.
//  3. WebSocket upgrade must succeed.
//
// After upgrade, NewConn + Hub.Register + Conn.Run handle the rest.
type WSHandler struct {
	Hub         *Hub
	Delegate    Delegate
	Logger      *slog.Logger
	CallTimeout time.Duration

	// AllowedOrigins, when non-nil, gates which Origin headers can
	// upgrade. Real chargers typically don't send Origin so an empty
	// origin is treated as "no Origin == accept" (websocket.AcceptOptions
	// behavior). Set this for browser-based test clients during dev.
	AllowedOrigins []string
}

// ServeHTTP implements http.Handler.
func (h *WSHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	chargePointID := chargePointIDFromPath(r.URL.Path)
	if chargePointID == "" {
		http.Error(w, "missing charge point identity in URL", http.StatusBadRequest)
		return
	}

	// We accept the connection only if the client signaled OCPP 1.6
	// in the subprotocol list. coder/websocket negotiates this for us
	// when we pass it the supported subprotocols below — if the
	// client offered a non-matching set, the handshake fails with the
	// well-known close code.
	opts := &websocket.AcceptOptions{
		Subprotocols:    []string{ocpp.SubprotocolHeader},
		OriginPatterns:  h.AllowedOrigins, // nil = same-origin
		CompressionMode: websocket.CompressionDisabled,
	}

	ws, err := websocket.Accept(w, r, opts)
	if err != nil {
		// websocket.Accept already wrote a 4xx/5xx; just log.
		h.Logger.Info("ws upgrade rejected",
			slog.String("cp", chargePointID),
			slog.String("err", err.Error()))
		return
	}

	if ws.Subprotocol() != ocpp.SubprotocolHeader {
		// Defense-in-depth: if Accept somehow handed us a connection
		// without the negotiated subprotocol, drop it. Spec mandates
		// the header.
		_ = ws.Close(websocket.StatusProtocolError, "ocpp1.6 subprotocol required")
		return
	}

	conn := NewConn(chargePointID, ws, h.Delegate, h.Logger, h.CallTimeout)

	if err := h.Hub.Register(conn); err != nil {
		_ = ws.Close(websocket.StatusGoingAway, "gateway shutting down")
		return
	}

	// Run blocks until the connection closes. We use a request-scoped
	// context so a Cloud Run termination signal (which cancels the
	// HTTP server's BaseContext) tears down active connections too.
	defer h.Hub.Unregister(conn)
	conn.Run(r.Context())
}

// chargePointIDFromPath extracts the path segment after "/ocpp/".
// Returns empty string if the URL doesn't match the pattern. Trims
// trailing slashes so /ocpp/CP001/ and /ocpp/CP001 resolve to "CP001".
func chargePointIDFromPath(p string) string {
	const prefix = "/ocpp/"
	if !strings.HasPrefix(p, prefix) {
		return ""
	}
	id := strings.TrimSuffix(p[len(prefix):], "/")
	if strings.Contains(id, "/") {
		// Reject paths with extra segments — protects against the
		// charger sending "/ocpp/CP001/extra" by mistake.
		return ""
	}
	return id
}

// IsClientGone reports whether err is the kind of WebSocket close
// that means "the charger closed the socket cleanly" — used by Conn
// callers to decide log severity.
func IsClientGone(err error) bool {
	if err == nil {
		return false
	}
	var ce websocket.CloseError
	if errors.As(err, &ce) {
		switch ce.Code {
		case websocket.StatusNormalClosure, websocket.StatusGoingAway:
			return true
		}
	}
	return errors.Is(err, context.Canceled)
}
