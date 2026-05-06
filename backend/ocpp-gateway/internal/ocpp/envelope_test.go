package ocpp

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestEnvelopeRoundTripCall(t *testing.T) {
	frame := []byte(`[2,"abc-123","BootNotification",{"chargePointVendor":"Vendor","chargePointModel":"M1"}]`)
	var got Envelope
	if err := json.Unmarshal(frame, &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got.Kind != MessageTypeCall {
		t.Errorf("Kind = %d, want Call", got.Kind)
	}
	if got.UniqueID != "abc-123" {
		t.Errorf("UniqueID = %q", got.UniqueID)
	}
	if got.Action != "BootNotification" {
		t.Errorf("Action = %q", got.Action)
	}

	// Re-encode and check shape — exact bytes can differ because
	// json.RawMessage may compact whitespace.
	out, err := json.Marshal(got)
	if err != nil {
		t.Fatalf("encode: %v", err)
	}
	if !strings.HasPrefix(string(out), `[2,"abc-123","BootNotification",`) {
		t.Errorf("re-encoded prefix wrong: %s", out)
	}
}

func TestEnvelopeRoundTripCallResult(t *testing.T) {
	frame := []byte(`[3,"abc-123",{"status":"Accepted","currentTime":"2026-05-01T00:00:00Z","interval":300}]`)
	var got Envelope
	if err := json.Unmarshal(frame, &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got.Kind != MessageTypeCallResult {
		t.Errorf("Kind = %d, want CallResult", got.Kind)
	}
	if got.UniqueID != "abc-123" {
		t.Errorf("UniqueID = %q", got.UniqueID)
	}
}

func TestEnvelopeRoundTripCallError(t *testing.T) {
	frame := []byte(`[4,"abc","NotImplemented","unsupported",{"hint":"upgrade firmware"}]`)
	var got Envelope
	if err := json.Unmarshal(frame, &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got.Kind != MessageTypeCallError {
		t.Errorf("Kind = %d, want CallError", got.Kind)
	}
	if got.ErrorCode != ErrorNotImplemented {
		t.Errorf("ErrorCode = %s", got.ErrorCode)
	}
	if got.ErrorDescription != "unsupported" {
		t.Errorf("ErrorDescription = %q", got.ErrorDescription)
	}
}

func TestEnvelopeUnknownErrorCodeCoercedToGeneric(t *testing.T) {
	frame := []byte(`[4,"abc","SomeNewError","details",{}]`)
	var got Envelope
	if err := json.Unmarshal(frame, &got); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if got.ErrorCode != ErrorGenericError {
		t.Errorf("expected GenericError coercion, got %s", got.ErrorCode)
	}
}

func TestEnvelopeRejectsMalformed(t *testing.T) {
	cases := []string{
		`{"kind":"call"}`,                // not array
		`[]`,                              // empty
		`[5,"abc"]`,                       // unknown messageTypeId
		`[2,"abc","Action"]`,              // Call missing payload
		`[2,"","Action",{}]`,              // empty uniqueId
		`[2,"abc","",{}]`,                 // empty action
		`[3,"abc"]`,                       // CallResult missing payload
		`[4,"abc","NotImplemented"]`,      // CallError missing description
	}
	for _, frame := range cases {
		var env Envelope
		if err := json.Unmarshal([]byte(frame), &env); err == nil {
			t.Errorf("expected error decoding %q", frame)
		}
	}
}

func TestNewCallValidatesInput(t *testing.T) {
	if _, err := NewCall("", "Action", json.RawMessage(`{}`)); err == nil {
		t.Error("expected error for empty uniqueID")
	}
	if _, err := NewCall("abc", "", json.RawMessage(`{}`)); err == nil {
		t.Error("expected error for empty action")
	}
	env, err := NewCall("abc", "Heartbeat", nil)
	if err != nil {
		t.Fatalf("unexpected: %v", err)
	}
	if string(env.Payload) != "{}" {
		t.Errorf("nil payload should default to {}, got %s", env.Payload)
	}
}
