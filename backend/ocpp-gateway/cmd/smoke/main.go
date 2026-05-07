// Command smoke runs an end-to-end OCPP smoke test against a
// locally-running Gateway. Reuses the same wire-format types the
// production code uses — if smoke ever decodes a frame the real
// Gateway can't, you've got a real bug, not a test artifact drift.
//
// Usage:
//
//	go run ./cmd/smoke
//	go run ./cmd/smoke -url ws://staging.example/ocpp/test-charger
//	go run ./cmd/smoke -firestore         # also verify Firestore docs
//	go run ./cmd/smoke -firestore -cleanup # ...and delete what we wrote
//
// Exit code is 0 when every scenario passes, 1 otherwise — paste it
// into CI any time the Gateway is reachable from the runner. Each
// scenario prints PASS / FAIL with a one-line reason; the final
// summary makes a single screenshot tell the whole story.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	cloudfirestore "cloud.google.com/go/firestore"
	"github.com/coder/websocket"
	"google.golang.org/api/option"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/sirawitchpoon/voltspot/backend/ocpp-gateway/internal/ocpp"
)

// CLI flags. Defaults assume `go run ./cmd/gateway` on the same
// laptop with the seeded Asoke EV Hub station from
// scripts/seed-stations.js.
var (
	flagURL = flag.String(
		"url",
		"ws://localhost:8080/ocpp/stn-bkk-01",
		"Gateway WebSocket URL — must include /ocpp/{chargePointId} suffix",
	)
	flagSubprotocol = flag.String(
		"subprotocol",
		"ocpp1.6",
		"WebSocket subprotocol header value",
	)
	flagTimeout = flag.Duration(
		"timeout",
		15*time.Second,
		"Per-frame send-and-receive timeout",
	)
	flagFirestore = flag.Bool(
		"firestore",
		false,
		"After OCPP frames pass, verify the resulting docs in Firestore",
	)
	flagCleanup = flag.Bool(
		"cleanup",
		false,
		"Delete the docs created by this run (only meaningful with -firestore)",
	)
	flagProjectID = flag.String(
		"project",
		envOr("FIREBASE_PROJECT_ID", ""),
		"Firebase project ID for -firestore verification",
	)
	flagSAPath = flag.String(
		"service-account",
		envOr("GOOGLE_APPLICATION_CREDENTIALS", ""),
		"Path to service-account JSON. Empty = use Application Default Credentials.",
	)
)

// ANSI escape sequences. Chosen to look right in iTerm + macOS
// Terminal + the GitHub Actions web log viewer (which honors them).
const (
	cReset  = "\033[0m"
	cRed    = "\033[31m"
	cGreen  = "\033[32m"
	cYellow = "\033[33m"
	cCyan   = "\033[36m"
	cBold   = "\033[1m"
	cDim    = "\033[2m"
)

// chargePointID is the path segment on the WS URL — extracted at
// startup so Firestore verification can address the right docs.
var chargePointID string

func main() {
	flag.Parse()
	chargePointID = extractChargePointID(*flagURL)
	if chargePointID == "" {
		exit("smoke: could not extract chargePointId from %s — URL must end in /ocpp/{cpId}", *flagURL)
	}

	header(fmt.Sprintf("Voltspot OCPP smoke test  ·  %s", *flagURL))

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	r := newRunner(ctx)
	r.run()

	if *flagFirestore {
		fmt.Println()
		header("Firestore verification")
		r.runFirestore(ctx)
	}

	fmt.Println()
	r.summary()

	if r.failed > 0 {
		os.Exit(1)
	}
}

// ─── Runner ──────────────────────────────────────────────────────────

type runner struct {
	ctx context.Context

	conn *websocket.Conn

	// Captured during the OCPP run — fed into Firestore checks later.
	transactionID int

	passed int
	failed int
}

func newRunner(ctx context.Context) *runner {
	return &runner{ctx: ctx}
}

// step runs fn under the per-frame timeout, prints PASS/FAIL with a
// short explanation, and updates the pass/fail counters.
func (r *runner) step(name string, fn func() error) {
	stepCtx, cancel := context.WithTimeout(r.ctx, *flagTimeout)
	defer cancel()

	// Print the row before fn() returns so the screen layout is stable
	// even if fn blocks.
	fmt.Printf("  %s%-46s%s ", cDim, name, cReset)

	type result struct{ err error }
	done := make(chan result, 1)
	go func() {
		done <- result{err: fn()}
	}()

	select {
	case res := <-done:
		if res.err != nil {
			fmt.Printf("%s%sFAIL%s  %s%s%s\n", cRed, cBold, cReset, cRed, res.err.Error(), cReset)
			r.failed++
			return
		}
		fmt.Printf("%s%sPASS%s\n", cGreen, cBold, cReset)
		r.passed++
	case <-stepCtx.Done():
		fmt.Printf("%s%sFAIL%s  %stimeout after %s%s\n",
			cRed, cBold, cReset, cRed, flagTimeout.String(), cReset)
		r.failed++
	}
}

// run executes the OCPP frame scenarios in order. Earlier failures
// cascade — there's no point sending MeterValues if StartTransaction
// never came back with a transactionId.
func (r *runner) run() {
	r.step("connect WebSocket", r.connect)
	if r.failed > 0 {
		return
	}
	defer func() { _ = r.conn.Close(websocket.StatusNormalClosure, "smoke done") }()

	r.step("BootNotification → Accepted", r.bootNotification)
	r.step("StatusNotification(connector=1, Available)", r.statusNotification)
	r.step("Heartbeat → currentTime", r.heartbeat)
	r.step("StartTransaction → Accepted, transactionId issued", r.startTransaction)
	r.step("MeterValues(5500 Wh) → ack", r.meterValues)
	r.step("StopTransaction(12000 Wh, reason=Local) → Accepted", r.stopTransaction)
}

// runFirestore checks the docs the gateway should have written. Only
// runs when -firestore is set; requires either ADC or an explicit
// service-account JSON.
func (r *runner) runFirestore(ctx context.Context) {
	if *flagProjectID == "" {
		r.step("Firestore: project ID present", func() error {
			return errors.New("set -project or FIREBASE_PROJECT_ID")
		})
		return
	}

	var opts []option.ClientOption
	if *flagSAPath != "" {
		opts = append(opts, option.WithCredentialsFile(*flagSAPath))
	}
	client, err := cloudfirestore.NewClient(ctx, *flagProjectID, opts...)
	if err != nil {
		r.step("Firestore: connect", func() error { return err })
		return
	}
	defer func() { _ = client.Close() }()

	r.step(
		fmt.Sprintf("/connector_status/%s_0  status=Available", chargePointID),
		func() error {
			return assertDocFields(ctx, client, "connector_status",
				fmt.Sprintf("%s_0", chargePointID),
				map[string]any{
					"status":      "Available",
					"errorCode":   "NoError",
					"connectorId": int64(0),
					"stationId":   chargePointID,
				})
		},
	)

	r.step(
		fmt.Sprintf("/connector_status/%s_1  status=Charging then cleared", chargePointID),
		func() error {
			// Charging is the steady-state right after StartTransaction;
			// after StopTransaction the gateway flips it to Finishing
			// and removes activeTransactionId. We accept either Charging
			// or Finishing — depending on whether StopTransaction's
			// Firestore write has caught up.
			snap, err := client.Collection("connector_status").
				Doc(fmt.Sprintf("%s_1", chargePointID)).Get(ctx)
			if err != nil {
				return err
			}
			data := snap.Data()
			st, _ := data["status"].(string)
			if st != "Charging" && st != "Finishing" {
				return fmt.Errorf("status = %q, want Charging or Finishing", st)
			}
			return nil
		},
	)

	r.step(
		fmt.Sprintf("/sessions/tx-%d  status=completed, costSatang>0", r.transactionID),
		func() error {
			if r.transactionID == 0 {
				return errors.New("StartTransaction didn't return a transactionId")
			}
			snap, err := client.Collection("sessions").
				Doc(fmt.Sprintf("tx-%d", r.transactionID)).Get(ctx)
			if err != nil {
				return err
			}
			data := snap.Data()
			if got, _ := data["status"].(string); got != "completed" {
				return fmt.Errorf("status = %q, want completed", got)
			}
			cost, _ := data["costSatang"].(int64)
			if cost <= 0 {
				return fmt.Errorf("costSatang = %d, want > 0", cost)
			}
			energy, _ := data["energyKWh"].(float64)
			if energy <= 0 {
				return fmt.Errorf("energyKWh = %v, want > 0", energy)
			}
			return nil
		},
	)

	if *flagCleanup {
		r.step("cleanup: delete connector_status + session docs", func() error {
			return cleanup(ctx, client, r.transactionID)
		})
	}
}

func (r *runner) summary() {
	total := r.passed + r.failed
	if r.failed == 0 {
		fmt.Printf("%s%s%d/%d PASSED%s\n", cGreen, cBold, r.passed, total, cReset)
		return
	}
	fmt.Printf("%s%s%d/%d PASSED · %d FAILED%s\n",
		cYellow, cBold, r.passed, total, r.failed, cReset)
}

// ─── OCPP scenarios ──────────────────────────────────────────────────

func (r *runner) connect() error {
	dialCtx, cancel := context.WithTimeout(r.ctx, *flagTimeout)
	defer cancel()
	c, _, err := websocket.Dial(dialCtx, *flagURL, &websocket.DialOptions{
		Subprotocols: []string{*flagSubprotocol},
	})
	if err != nil {
		return err
	}
	if c.Subprotocol() != *flagSubprotocol {
		_ = c.Close(websocket.StatusProtocolError, "")
		return fmt.Errorf("server negotiated subprotocol %q, want %q",
			c.Subprotocol(), *flagSubprotocol)
	}
	r.conn = c
	return nil
}

func (r *runner) bootNotification() error {
	resp, err := r.call("boot-1", ocpp.ActionBootNotification, ocpp.BootNotificationRequest{
		ChargePointVendor: "VoltspotSmoke",
		ChargePointModel:  "X1",
	})
	if err != nil {
		return err
	}
	var body ocpp.BootNotificationResponse
	if err := json.Unmarshal(resp, &body); err != nil {
		return fmt.Errorf("decode response: %w", err)
	}
	if body.Status != ocpp.RegistrationAccepted {
		return fmt.Errorf("status = %q, want Accepted", body.Status)
	}
	if body.Interval <= 0 {
		return fmt.Errorf("interval = %d, want > 0", body.Interval)
	}
	if body.CurrentTime.IsZero() {
		return errors.New("currentTime missing")
	}
	return nil
}

func (r *runner) statusNotification() error {
	resp, err := r.call("status-1", ocpp.ActionStatusNotification, ocpp.StatusNotificationRequest{
		ConnectorID: 1,
		ErrorCode:   ocpp.ErrCodeNoError,
		Status:      ocpp.StatusAvailable,
	})
	if err != nil {
		return err
	}
	// Spec: empty {} payload — we accept anything that decodes.
	var body ocpp.StatusNotificationResponse
	if err := json.Unmarshal(resp, &body); err != nil {
		return fmt.Errorf("decode response: %w", err)
	}
	return nil
}

func (r *runner) heartbeat() error {
	resp, err := r.call("hb-1", ocpp.ActionHeartbeat, ocpp.HeartbeatRequest{})
	if err != nil {
		return err
	}
	var body ocpp.HeartbeatResponse
	if err := json.Unmarshal(resp, &body); err != nil {
		return fmt.Errorf("decode response: %w", err)
	}
	if body.CurrentTime.IsZero() {
		return errors.New("currentTime missing")
	}
	return nil
}

func (r *runner) startTransaction() error {
	resp, err := r.call("start-1", ocpp.ActionStartTransaction, ocpp.StartTransactionRequest{
		ConnectorID: 1,
		IDTag:       "smoke-test-rfid",
		MeterStart:  0,
		Timestamp:   ocpp.Now(),
	})
	if err != nil {
		return err
	}
	var body ocpp.StartTransactionResponse
	if err := json.Unmarshal(resp, &body); err != nil {
		return fmt.Errorf("decode response: %w", err)
	}
	if body.IDTagInfo.Status != ocpp.AuthAccepted {
		return fmt.Errorf("idTagInfo.status = %q, want Accepted", body.IDTagInfo.Status)
	}
	if body.TransactionID <= 0 {
		return fmt.Errorf("transactionId = %d, want > 0", body.TransactionID)
	}
	r.transactionID = body.TransactionID
	return nil
}

func (r *runner) meterValues() error {
	if r.transactionID == 0 {
		return errors.New("no transactionId from StartTransaction")
	}
	measurand := "Energy.Active.Import.Register"
	unit := "Wh"
	txID := r.transactionID
	_, err := r.call("meter-1", ocpp.ActionMeterValues, ocpp.MeterValuesRequest{
		ConnectorID:   1,
		TransactionID: &txID,
		MeterValue: []ocpp.MeterValue{{
			Timestamp: ocpp.Now(),
			SampledValue: []ocpp.SampledValue{{
				Value:     "5500",
				Measurand: &measurand,
				Unit:      &unit,
			}},
		}},
	})
	return err
}

func (r *runner) stopTransaction() error {
	if r.transactionID == 0 {
		return errors.New("no transactionId from StartTransaction")
	}
	reason := ocpp.StopLocal
	resp, err := r.call("stop-1", ocpp.ActionStopTransaction, ocpp.StopTransactionRequest{
		TransactionID: r.transactionID,
		MeterStop:     12000,
		Timestamp:     ocpp.Now(),
		Reason:        &reason,
	})
	if err != nil {
		return err
	}
	var body ocpp.StopTransactionResponse
	if err := json.Unmarshal(resp, &body); err != nil {
		return fmt.Errorf("decode response: %w", err)
	}
	if body.IDTagInfo == nil || body.IDTagInfo.Status != ocpp.AuthAccepted {
		return fmt.Errorf("idTagInfo missing or not Accepted")
	}
	// Give the gateway's async Firestore write a moment to settle so
	// downstream Firestore checks aren't racing it. 500ms is more than
	// enough for a localhost roundtrip.
	time.Sleep(500 * time.Millisecond)
	return nil
}

// ─── Wire helpers ────────────────────────────────────────────────────

// call sends a Call frame and returns the matching CallResult payload.
// Times out via the runner's per-step context.
func (r *runner) call(uniqueID string, action ocpp.Action, payload any) (json.RawMessage, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("marshal payload: %w", err)
	}
	env, err := ocpp.NewCall(uniqueID, string(action), body)
	if err != nil {
		return nil, err
	}
	frame, err := json.Marshal(env)
	if err != nil {
		return nil, fmt.Errorf("marshal envelope: %w", err)
	}
	if err := r.conn.Write(r.ctx, websocket.MessageText, frame); err != nil {
		return nil, fmt.Errorf("ws write: %w", err)
	}

	// Wait for the matching response. The gateway is single-threaded
	// per connection from our perspective — frames come back in the
	// order we send them — so we accept the next CallResult/Error.
	for {
		_, data, err := r.conn.Read(r.ctx)
		if err != nil {
			return nil, fmt.Errorf("ws read: %w", err)
		}
		var got ocpp.Envelope
		if err := json.Unmarshal(data, &got); err != nil {
			return nil, fmt.Errorf("decode envelope: %w", err)
		}
		switch got.Kind {
		case ocpp.MessageTypeCallResult:
			if got.UniqueID != uniqueID {
				// Drop stragglers from a previous message and keep waiting.
				continue
			}
			return got.Payload, nil
		case ocpp.MessageTypeCallError:
			return nil, fmt.Errorf("CallError %s: %s", got.ErrorCode, got.ErrorDescription)
		default:
			// Inbound Call from the server — not expected in this smoke
			// test (we don't issue RemoteStart/Stop here). Drop and continue.
			continue
		}
	}
}

// ─── Firestore helpers ───────────────────────────────────────────────

// assertDocFields fetches a document and checks that each key in
// `want` matches the value in the doc. Numeric Int comparisons
// tolerate Firestore's int64-as-int64 quirk.
func assertDocFields(
	ctx context.Context,
	client *cloudfirestore.Client,
	collection, docID string,
	want map[string]any,
) error {
	snap, err := client.Collection(collection).Doc(docID).Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return fmt.Errorf("doc %s/%s not found", collection, docID)
		}
		return err
	}
	data := snap.Data()
	for k, v := range want {
		got, ok := data[k]
		if !ok {
			return fmt.Errorf("field %q missing", k)
		}
		if !equalLoose(got, v) {
			return fmt.Errorf("field %q = %v, want %v", k, got, v)
		}
	}
	return nil
}

// equalLoose compares two `any` values with a small dose of tolerance
// for the int64 / int / float64 mismatches Firestore returns.
func equalLoose(got, want any) bool {
	switch w := want.(type) {
	case int:
		return toInt64(got) == int64(w)
	case int64:
		return toInt64(got) == w
	case float64:
		switch g := got.(type) {
		case float64:
			return g == w
		case int64:
			return float64(g) == w
		case int:
			return float64(g) == w
		}
		return false
	}
	return got == want
}

func toInt64(v any) int64 {
	switch n := v.(type) {
	case int:
		return int64(n)
	case int64:
		return n
	case float64:
		return int64(n)
	}
	return 0
}

func cleanup(ctx context.Context, client *cloudfirestore.Client, txID int) error {
	docs := []*cloudfirestore.DocumentRef{
		client.Collection("connector_status").Doc(fmt.Sprintf("%s_0", chargePointID)),
		client.Collection("connector_status").Doc(fmt.Sprintf("%s_1", chargePointID)),
	}
	if txID > 0 {
		docs = append(docs, client.Collection("sessions").Doc(fmt.Sprintf("tx-%d", txID)))
	}
	for _, ref := range docs {
		if _, err := ref.Delete(ctx); err != nil {
			return fmt.Errorf("delete %s: %w", ref.Path, err)
		}
	}
	return nil
}

// ─── small utilities ─────────────────────────────────────────────────

func header(s string) {
	fmt.Printf("%s%s%s%s\n", cBold, cCyan, s, cReset)
	fmt.Println(strings.Repeat("─", len(stripANSI(s))))
}

func stripANSI(s string) string {
	// Just for header underline width — fine if a stray escape slips
	// through, Unicode rune count would be more correct but ASCII is
	// good enough for what we print.
	return s
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func extractChargePointID(rawURL string) string {
	const marker = "/ocpp/"
	idx := strings.Index(rawURL, marker)
	if idx == -1 {
		return ""
	}
	rest := strings.TrimSuffix(rawURL[idx+len(marker):], "/")
	if i := strings.Index(rest, "/"); i != -1 {
		return rest[:i]
	}
	return rest
}

func exit(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(2)
}
