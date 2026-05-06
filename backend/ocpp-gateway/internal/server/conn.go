// Package server hosts the WebSocket and REST HTTP surfaces of the
// Gateway. Connection lifecycle, message routing, and reconnect
// handling all live here. Business logic (what to do with a Boot or a
// MeterValues) is kept in delegates so the server stays transport-only.
package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/coder/websocket"
	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/ocpp"
)

// pendingCall ties an outbound Call to the goroutine waiting for its
// CallResult / CallError. timer is fired by callTimeout to surface a
// transport-level timeout if the charger never replies.
type pendingCall struct {
	uniqueID string
	respond  chan ocpp.Envelope
	timer    *time.Timer
}

// Conn wraps a single charger's WebSocket connection. One goroutine
// owns reads (the read loop), another owns writes (the write loop).
// All other methods are safe for concurrent use.
//
// Lifecycle:
//
//	NewConn → run() in its own goroutine → emits frames to the
//	delegate via Inbound* → close on read error or Close().
//
// Reconnect: when a charger with the same chargePointID opens a new
// WebSocket, the Hub calls Close on the old Conn before swapping in
// the new one. The old Conn cancels in-flight Calls with
// ErrConnectionClosed.
type Conn struct {
	chargePointID string
	ws            *websocket.Conn
	logger        *slog.Logger
	delegate      Delegate
	callTimeout   time.Duration

	// writeCh is buffered so a slow charger can't block the read loop's
	// reply path. If the buffer fills the connection is closed because
	// the charger isn't keeping up.
	writeCh chan ocpp.Envelope

	mu      sync.Mutex
	pending map[string]*pendingCall // outbound Calls awaiting response
	closed  bool
	closeErr error

	closeOnce sync.Once
	done      chan struct{}

	// lastSeen is updated on every inbound frame. The Hub watches this
	// to decide when to close idle connections (heartbeat timeout).
	lastSeenMu sync.RWMutex
	lastSeen   time.Time
}

// Delegate is the business interface the Conn calls into when a Call
// arrives from the charger or the connection lifecycle changes.
// Implementations are responsible for crafting the OCPP response
// payload; everything transport-related (envelope, uniqueId, error
// code) is handled by the Conn.
type Delegate interface {
	OnConnect(ctx context.Context, chargePointID string)
	OnDisconnect(ctx context.Context, chargePointID string, cause error)

	// OnCall handles an inbound Call from the charger. Return either a
	// successful payload (action-specific Response struct) or a
	// CallError. payload contains the raw JSON body.
	OnCall(ctx context.Context, chargePointID string, action ocpp.Action, payload json.RawMessage) (responsePayload any, callErr *CallError)
}

// CallError is what a Delegate returns to map into the OCPP CallError
// frame format. errorDescription should be a human-readable string;
// errorDetails is encoded as the details JSON object.
type CallError struct {
	Code        ocpp.CallErrorCode
	Description string
	Details     json.RawMessage
}

// NewConn wraps a freshly-upgraded WebSocket. Caller is responsible
// for calling Run() in its own goroutine.
func NewConn(
	chargePointID string,
	ws *websocket.Conn,
	delegate Delegate,
	logger *slog.Logger,
	callTimeout time.Duration,
) *Conn {
	if callTimeout <= 0 {
		callTimeout = 30 * time.Second
	}
	return &Conn{
		chargePointID: chargePointID,
		ws:            ws,
		logger:        logger.With(slog.String("cp", chargePointID)),
		delegate:      delegate,
		callTimeout:   callTimeout,
		writeCh:       make(chan ocpp.Envelope, 32),
		pending:       make(map[string]*pendingCall),
		done:          make(chan struct{}),
		lastSeen:      time.Now(),
	}
}

// ChargePointID returns the identity portion of the WS URL.
func (c *Conn) ChargePointID() string { return c.chargePointID }

// LastSeen returns the timestamp of the most recent inbound frame.
// Hub uses this for idle-connection cleanup.
func (c *Conn) LastSeen() time.Time {
	c.lastSeenMu.RLock()
	defer c.lastSeenMu.RUnlock()
	return c.lastSeen
}

// Run is the connection's main loop. Spawns a write pump in a
// goroutine, then blocks on the read pump until the socket closes
// or the context is cancelled. When Run returns, the connection is
// fully drained (no goroutines outstanding).
func (c *Conn) Run(ctx context.Context) {
	c.delegate.OnConnect(ctx, c.chargePointID)

	// Create a derived context the write pump can also watch so a
	// caller-cancelled context tears both loops down.
	connCtx, cancel := context.WithCancel(ctx)
	defer cancel()

	writeDone := make(chan struct{})
	go func() {
		defer close(writeDone)
		c.writePump(connCtx)
	}()

	readErr := c.readPump(connCtx)
	c.closeWith(readErr)

	// Wait for write pump to drain before signalling done.
	<-writeDone
	close(c.done)

	c.delegate.OnDisconnect(ctx, c.chargePointID, readErr)
}

// Done returns a channel that's closed when Run exits.
func (c *Conn) Done() <-chan struct{} { return c.done }

// Send queues a Call to the charger and waits for its response.
// Returns the raw response payload on success, or:
//   - ErrCallTimeout if the charger doesn't reply within callTimeout
//   - ErrConnectionClosed if the WS closes while waiting
//   - *CallErrorReceived if the charger replies with a CallError frame
//   - context error if ctx is cancelled
func (c *Conn) Send(ctx context.Context, action ocpp.Action, payload any) (json.RawMessage, error) {
	if !action.IsCSMSInitiated() {
		return nil, fmt.Errorf("server: %s is not a CSMS-initiated action", action)
	}

	encoded, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("server: marshal call payload: %w", err)
	}
	uniqueID := newUniqueID()
	env, err := ocpp.NewCall(uniqueID, string(action), encoded)
	if err != nil {
		return nil, err
	}

	respCh := make(chan ocpp.Envelope, 1)
	pc := &pendingCall{uniqueID: uniqueID, respond: respCh}

	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return nil, ErrConnectionClosed
	}
	c.pending[uniqueID] = pc
	c.mu.Unlock()

	pc.timer = time.AfterFunc(c.callTimeout, func() {
		c.removePending(uniqueID, ocpp.Envelope{
			Kind:             ocpp.MessageTypeCallError,
			UniqueID:         uniqueID,
			ErrorCode:        ocpp.ErrorGenericError,
			ErrorDescription: "timeout",
		})
	})

	if err := c.queueWrite(ctx, env); err != nil {
		c.removePending(uniqueID, ocpp.Envelope{}) // discard ghost reply
		pc.timer.Stop()
		return nil, err
	}

	select {
	case resp := <-respCh:
		switch resp.Kind {
		case ocpp.MessageTypeCallResult:
			return resp.Payload, nil
		case ocpp.MessageTypeCallError:
			if resp.ErrorDescription == "timeout" {
				return nil, ErrCallTimeout
			}
			return nil, &CallErrorReceived{
				Code:        resp.ErrorCode,
				Description: resp.ErrorDescription,
				Details:     resp.Payload,
			}
		default:
			return nil, fmt.Errorf("server: unexpected response kind %d", resp.Kind)
		}
	case <-ctx.Done():
		c.removePending(uniqueID, ocpp.Envelope{})
		pc.timer.Stop()
		return nil, ctx.Err()
	}
}

// ─── internal ─────────────────────────────────────────────────────────

func (c *Conn) readPump(ctx context.Context) error {
	for {
		_, data, err := c.ws.Read(ctx)
		if err != nil {
			return err
		}
		c.touch()

		var env ocpp.Envelope
		if err := json.Unmarshal(data, &env); err != nil {
			c.logger.Warn("malformed OCPP frame", slog.String("err", err.Error()))
			// Malformed frames don't carry a uniqueId we can attach to a
			// CallError reliably — drop and keep the connection up.
			continue
		}

		switch env.Kind {
		case ocpp.MessageTypeCall:
			c.handleInboundCall(ctx, env)
		case ocpp.MessageTypeCallResult, ocpp.MessageTypeCallError:
			c.routeResponse(env)
		default:
			c.logger.Warn("unknown envelope kind", slog.Any("kind", env.Kind))
		}
	}
}

func (c *Conn) writePump(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case env, ok := <-c.writeCh:
			if !ok {
				return
			}
			data, err := json.Marshal(env)
			if err != nil {
				c.logger.Error("marshal envelope", slog.String("err", err.Error()))
				continue
			}
			if err := c.ws.Write(ctx, websocket.MessageText, data); err != nil {
				c.logger.Error("ws write", slog.String("err", err.Error()))
				return
			}
		}
	}
}

// handleInboundCall dispatches a charger-initiated Call to the
// Delegate, then writes either a CallResult or a CallError back.
// Each Call gets its own goroutine so a slow Delegate doesn't head-of-
// line block other frames on the same connection.
func (c *Conn) handleInboundCall(ctx context.Context, env ocpp.Envelope) {
	go func() {
		action := ocpp.Action(env.Action)

		respPayload, callErr := c.delegate.OnCall(ctx, c.chargePointID, action, env.Payload)

		if callErr != nil {
			out := ocpp.NewCallError(env.UniqueID, callErr.Code, callErr.Description, callErr.Details)
			_ = c.queueWrite(ctx, out)
			return
		}

		body, err := json.Marshal(respPayload)
		if err != nil {
			c.logger.Error("marshal response payload",
				slog.String("action", env.Action),
				slog.String("err", err.Error()))
			out := ocpp.NewCallError(env.UniqueID, ocpp.ErrorInternalError, "marshal response", nil)
			_ = c.queueWrite(ctx, out)
			return
		}
		out := ocpp.NewCallResult(env.UniqueID, body)
		_ = c.queueWrite(ctx, out)
	}()
}

func (c *Conn) routeResponse(env ocpp.Envelope) {
	c.mu.Lock()
	pc, ok := c.pending[env.UniqueID]
	delete(c.pending, env.UniqueID)
	c.mu.Unlock()

	if !ok {
		c.logger.Warn("response for unknown uniqueId", slog.String("id", env.UniqueID))
		return
	}
	pc.timer.Stop()
	select {
	case pc.respond <- env:
	default:
		// caller already gave up — drop quietly
	}
}

func (c *Conn) removePending(uniqueID string, deliver ocpp.Envelope) {
	c.mu.Lock()
	pc, ok := c.pending[uniqueID]
	delete(c.pending, uniqueID)
	c.mu.Unlock()
	if !ok {
		return
	}
	if deliver.Kind != 0 {
		select {
		case pc.respond <- deliver:
		default:
		}
	}
}

func (c *Conn) queueWrite(ctx context.Context, env ocpp.Envelope) error {
	select {
	case c.writeCh <- env:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	default:
		// Queue full — close the connection so the charger reconnects
		// instead of falling further behind.
		c.logger.Warn("write queue full, closing connection")
		c.closeWith(ErrWriteQueueFull)
		return ErrWriteQueueFull
	}
}

func (c *Conn) closeWith(cause error) {
	c.closeOnce.Do(func() {
		c.mu.Lock()
		c.closed = true
		c.closeErr = cause
		// Cancel every pending Call so Send returns instead of leaking.
		for id, pc := range c.pending {
			pc.timer.Stop()
			select {
			case pc.respond <- ocpp.Envelope{
				Kind:             ocpp.MessageTypeCallError,
				UniqueID:         id,
				ErrorCode:        ocpp.ErrorInternalError,
				ErrorDescription: "connection closed",
			}:
			default:
			}
			delete(c.pending, id)
		}
		c.mu.Unlock()

		// Close the WebSocket. coder/websocket Close is idempotent.
		_ = c.ws.Close(websocket.StatusNormalClosure, "")
		// Signal the write pump to exit. Use a separate channel close
		// so any select still sees it.
		// (writeCh is closed only here so the write pump's range loop
		// exits cleanly.)
		close(c.writeCh)
	})
}

func (c *Conn) touch() {
	now := time.Now()
	c.lastSeenMu.Lock()
	c.lastSeen = now
	c.lastSeenMu.Unlock()
}

// Close shuts the connection down. Pending Sends return
// ErrConnectionClosed. Idempotent.
func (c *Conn) Close() {
	c.closeWith(ErrConnectionClosed)
}

// ─── errors ───────────────────────────────────────────────────────────

// ErrConnectionClosed is returned by Send if the connection is gone.
var ErrConnectionClosed = errors.New("server: connection closed")

// ErrCallTimeout is returned by Send when the charger doesn't reply.
var ErrCallTimeout = errors.New("server: call timeout")

// ErrWriteQueueFull is returned by Send if the local write buffer is
// saturated — usually means the charger is processing too slowly.
var ErrWriteQueueFull = errors.New("server: write queue full")

// CallErrorReceived wraps a CallError frame received from the charger
// in response to one of our Calls.
type CallErrorReceived struct {
	Code        ocpp.CallErrorCode
	Description string
	Details     json.RawMessage
}

func (e *CallErrorReceived) Error() string {
	return fmt.Sprintf("ocpp call error %s: %s", e.Code, e.Description)
}
