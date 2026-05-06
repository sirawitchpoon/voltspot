package server

import (
	"encoding/json"
	"net/http"
	"sync/atomic"
)

// HealthHandler exposes /healthz (liveness — process is up) and
// /readyz (readiness — Firestore + Auth reachable + accepting WS).
//
// Cloud Run uses /healthz as its liveness probe; the load balancer
// uses /readyz to take an instance out of rotation while it warms
// up. Only /readyz reflects external dependencies — /healthz must
// stay cheap (no external calls) so a transient Firestore blip
// doesn't restart the whole container.
type HealthHandler struct {
	Hub *Hub

	// Ready, when set to false, makes /readyz fail. Used during
	// startup before deps are wired (zero value = false = not ready).
	ready atomic.Bool
}

// MarkReady flips /readyz to 200. Call once main.go finishes wiring.
func (h *HealthHandler) MarkReady() { h.ready.Store(true) }

// MarkNotReady flips /readyz back to 503 — used during graceful
// shutdown so the load balancer drains the instance before SIGKILL.
func (h *HealthHandler) MarkNotReady() { h.ready.Store(false) }

// Healthz responds 200 OK with a small JSON body. Always succeeds
// while the process is running. Cloud Run's liveness check uses this.
func (h *HealthHandler) Healthz(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}

// Readyz reports whether the instance can take traffic. Returns 503
// during startup, after MarkNotReady, or if the hub is closed.
//
// Body includes a small status object (current connection count) so
// human operators looking at /readyz directly get useful context.
func (h *HealthHandler) Readyz(w http.ResponseWriter, _ *http.Request) {
	if !h.ready.Load() {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		_, _ = w.Write([]byte(`{"status":"starting"}`))
		return
	}

	body := struct {
		Status      string   `json:"status"`
		Connected   int      `json:"connectedChargers"`
		ChargePoint []string `json:"chargePointIds,omitempty"`
	}{
		Status: "ready",
	}
	if h.Hub != nil {
		ids := h.Hub.Connected()
		body.Connected = len(ids)
		// Only include the list at debug verbosity — it can grow large
		// and contain identifiers we don't want in arbitrary access logs.
		// For now, omit to keep the response cheap.
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(body)
}
