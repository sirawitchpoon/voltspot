package server

import (
	"context"
	"errors"
	"sync"
	"time"
)

// Hub is the in-memory registry of active charger connections. One
// per Gateway process; shared by the WS handler (registers
// connections), the REST handler (looks them up to send remote
// commands), and the heartbeat watchdog (closes idle connections).
//
// Reconnect handling: when a charger dials in with a chargePointID
// that's already registered, the older Conn is closed and replaced.
// This is the OCPP-J behavior chargers expect — after a flaky
// network they reconnect with the same identity and continue.
type Hub struct {
	mu      sync.RWMutex
	conns   map[string]*Conn
	closed  bool
}

// NewHub returns an empty hub. Callers can then call Register /
// Lookup / Close as needed.
func NewHub() *Hub {
	return &Hub{conns: make(map[string]*Conn)}
}

// Register inserts conn into the hub. If a connection already exists
// for the same chargePointID it's closed first (handover). Returns
// ErrHubClosed if the hub has been shut down.
func (h *Hub) Register(conn *Conn) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.closed {
		return ErrHubClosed
	}
	if existing, ok := h.conns[conn.ChargePointID()]; ok {
		// Close the old connection asynchronously so the new one isn't
		// blocked waiting for the old write pump to drain.
		go existing.Close()
	}
	h.conns[conn.ChargePointID()] = conn
	return nil
}

// Unregister removes conn if and only if it's still the registered
// instance for its chargePointID. This guards against a race where
// a reconnect has already replaced the conn and a slow Run() exits
// after the new one registered.
func (h *Hub) Unregister(conn *Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.conns[conn.ChargePointID()] == conn {
		delete(h.conns, conn.ChargePointID())
	}
}

// Lookup returns the active connection for chargePointID, or nil if
// none. Callers must not retain the *Conn beyond the immediate
// operation — the hub may evict it at any time.
func (h *Hub) Lookup(chargePointID string) *Conn {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.conns[chargePointID]
}

// Connected returns the chargePointIDs currently online. Used by
// /readyz to expose connection count for monitoring.
func (h *Hub) Connected() []string {
	h.mu.RLock()
	defer h.mu.RUnlock()
	out := make([]string, 0, len(h.conns))
	for id := range h.conns {
		out = append(out, id)
	}
	return out
}

// Close drains every active connection. Used during graceful shutdown
// — Cloud Run's SIGTERM gives the container 10 seconds to settle, so
// we close fast and let chargers reconnect to the next instance.
func (h *Hub) Close() {
	h.mu.Lock()
	if h.closed {
		h.mu.Unlock()
		return
	}
	h.closed = true
	conns := make([]*Conn, 0, len(h.conns))
	for _, c := range h.conns {
		conns = append(conns, c)
	}
	h.conns = nil
	h.mu.Unlock()

	for _, c := range conns {
		c.Close()
	}
}

// StartIdleSweeper periodically closes connections that haven't
// emitted a frame in idleAfter. Caller cancels ctx to stop the
// sweeper. interval should be a fraction of idleAfter (e.g.
// idleAfter/4) so a connection isn't left lingering most of an
// interval after it goes silent.
//
// OCPP heartbeats happen every 300s by spec default. Setting
// idleAfter ≥ 600s tolerates one missed heartbeat before evicting.
func (h *Hub) StartIdleSweeper(ctx context.Context, interval, idleAfter time.Duration) {
	go func() {
		t := time.NewTicker(interval)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				h.evictIdle(idleAfter)
			}
		}
	}()
}

func (h *Hub) evictIdle(idleAfter time.Duration) {
	cutoff := time.Now().Add(-idleAfter)
	h.mu.RLock()
	candidates := make([]*Conn, 0)
	for _, c := range h.conns {
		if c.LastSeen().Before(cutoff) {
			candidates = append(candidates, c)
		}
	}
	h.mu.RUnlock()

	for _, c := range candidates {
		c.Close()
	}
}

// ErrHubClosed is returned by Register if the hub has been shut down.
var ErrHubClosed = errors.New("server: hub closed")
