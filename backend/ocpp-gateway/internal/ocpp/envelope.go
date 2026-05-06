package ocpp

import (
	"encoding/json"
	"errors"
	"fmt"
)

// MessageType is the integer that prefixes every OCPP-J wire frame.
// Defined in OCPP-J spec §4.2.
type MessageType int

const (
	MessageTypeCall       MessageType = 2
	MessageTypeCallResult MessageType = 3
	MessageTypeCallError  MessageType = 4
)

// CallErrorCode enumerates the standard OCPP-J errorCode strings (spec
// §4.4). Chargers that reply to a Call with an unknown errorCode are
// coerced to GenericError on decode — same behavior as the iOS client
// — so callers always see a known value.
type CallErrorCode string

const (
	ErrorNotImplemented                CallErrorCode = "NotImplemented"
	ErrorNotSupported                  CallErrorCode = "NotSupported"
	ErrorInternalError                 CallErrorCode = "InternalError"
	ErrorProtocolError                 CallErrorCode = "ProtocolError"
	ErrorSecurityError                 CallErrorCode = "SecurityError"
	ErrorFormationViolation            CallErrorCode = "FormationViolation"
	ErrorPropertyConstraintViolation   CallErrorCode = "PropertyConstraintViolation"
	ErrorOccurenceConstraintViolation  CallErrorCode = "OccurenceConstraintViolation"
	ErrorTypeConstraintViolation       CallErrorCode = "TypeConstraintViolation"
	ErrorGenericError                  CallErrorCode = "GenericError"
)

// IsKnown reports whether the code is one of the spec-defined values.
// Use to decide whether to log a "received unknown error code" warning
// or pass the value through unchanged.
func (c CallErrorCode) IsKnown() bool {
	switch c {
	case ErrorNotImplemented,
		ErrorNotSupported,
		ErrorInternalError,
		ErrorProtocolError,
		ErrorSecurityError,
		ErrorFormationViolation,
		ErrorPropertyConstraintViolation,
		ErrorOccurenceConstraintViolation,
		ErrorTypeConstraintViolation,
		ErrorGenericError:
		return true
	}
	return false
}

// Envelope is one OCPP-J wire frame. Exactly one of the three Kind
// values is meaningful at any time and the rest of the fields are
// populated accordingly:
//
//   - Call:        UniqueID, Action, Payload
//   - CallResult:  UniqueID, Payload
//   - CallError:   UniqueID, ErrorCode, ErrorDescription, Payload(=details)
//
// Payload is held as raw json.RawMessage so the envelope layer stays
// payload-agnostic; the surrounding code handles action-specific
// (un)marshalling.
type Envelope struct {
	Kind             MessageType
	UniqueID         string
	Action           string          // Call only
	ErrorCode        CallErrorCode   // CallError only
	ErrorDescription string          // CallError only
	Payload          json.RawMessage // empty {} when absent
}

// NewCall is a small constructor that validates required fields up
// front so misuses (empty action, missing payload) fail fast.
func NewCall(uniqueID, action string, payload json.RawMessage) (Envelope, error) {
	if uniqueID == "" {
		return Envelope{}, errors.New("ocpp: Call uniqueID is required")
	}
	if action == "" {
		return Envelope{}, errors.New("ocpp: Call action is required")
	}
	if len(payload) == 0 {
		payload = json.RawMessage("{}")
	}
	return Envelope{
		Kind:     MessageTypeCall,
		UniqueID: uniqueID,
		Action:   action,
		Payload:  payload,
	}, nil
}

// NewCallResult constructs a successful response to an inbound Call.
func NewCallResult(uniqueID string, payload json.RawMessage) Envelope {
	if len(payload) == 0 {
		payload = json.RawMessage("{}")
	}
	return Envelope{
		Kind:     MessageTypeCallResult,
		UniqueID: uniqueID,
		Payload:  payload,
	}
}

// NewCallError constructs a CallError reply. description must be set
// (spec §4.4); details may be nil and is encoded as `{}` on the wire.
func NewCallError(uniqueID string, code CallErrorCode, description string, details json.RawMessage) Envelope {
	if len(details) == 0 {
		details = json.RawMessage("{}")
	}
	return Envelope{
		Kind:             MessageTypeCallError,
		UniqueID:         uniqueID,
		ErrorCode:        code,
		ErrorDescription: description,
		Payload:          details,
	}
}

// MarshalJSON encodes the envelope as the heterogeneous JSON array
// the OCPP-J spec mandates. UniqueID is always at index 1; the rest
// of the layout depends on Kind.
func (e Envelope) MarshalJSON() ([]byte, error) {
	switch e.Kind {
	case MessageTypeCall:
		return json.Marshal([]any{
			int(MessageTypeCall),
			e.UniqueID,
			e.Action,
			rawOrEmpty(e.Payload),
		})
	case MessageTypeCallResult:
		return json.Marshal([]any{
			int(MessageTypeCallResult),
			e.UniqueID,
			rawOrEmpty(e.Payload),
		})
	case MessageTypeCallError:
		return json.Marshal([]any{
			int(MessageTypeCallError),
			e.UniqueID,
			string(e.ErrorCode),
			e.ErrorDescription,
			rawOrEmpty(e.Payload),
		})
	default:
		return nil, fmt.Errorf("ocpp: unknown envelope kind %d", e.Kind)
	}
}

// UnmarshalJSON parses an OCPP-J wire frame. Strict validation —
// malformed arrays return an error so the connection layer can decide
// whether to send a CallError back or close the socket.
func (e *Envelope) UnmarshalJSON(data []byte) error {
	var raw []json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return fmt.Errorf("ocpp: envelope must be a JSON array: %w", err)
	}
	if len(raw) < 2 {
		return errors.New("ocpp: envelope array too short")
	}

	var typeRaw int
	if err := json.Unmarshal(raw[0], &typeRaw); err != nil {
		return fmt.Errorf("ocpp: envelope[0] not an integer: %w", err)
	}
	var uniqueID string
	if err := json.Unmarshal(raw[1], &uniqueID); err != nil {
		return fmt.Errorf("ocpp: envelope[1] not a string: %w", err)
	}
	if uniqueID == "" {
		return errors.New("ocpp: envelope uniqueID is empty")
	}

	switch MessageType(typeRaw) {
	case MessageTypeCall:
		if len(raw) != 4 {
			return fmt.Errorf("ocpp: Call must have 4 elements, got %d", len(raw))
		}
		var action string
		if err := json.Unmarshal(raw[2], &action); err != nil {
			return fmt.Errorf("ocpp: Call action not a string: %w", err)
		}
		if action == "" {
			return errors.New("ocpp: Call action is empty")
		}
		e.Kind = MessageTypeCall
		e.UniqueID = uniqueID
		e.Action = action
		e.Payload = append(e.Payload[:0], raw[3]...)
		return nil

	case MessageTypeCallResult:
		if len(raw) != 3 {
			return fmt.Errorf("ocpp: CallResult must have 3 elements, got %d", len(raw))
		}
		e.Kind = MessageTypeCallResult
		e.UniqueID = uniqueID
		e.Payload = append(e.Payload[:0], raw[2]...)
		return nil

	case MessageTypeCallError:
		if len(raw) < 4 || len(raw) > 5 {
			return fmt.Errorf("ocpp: CallError must have 4 or 5 elements, got %d", len(raw))
		}
		var codeStr, description string
		if err := json.Unmarshal(raw[2], &codeStr); err != nil {
			return fmt.Errorf("ocpp: CallError errorCode not a string: %w", err)
		}
		if err := json.Unmarshal(raw[3], &description); err != nil {
			return fmt.Errorf("ocpp: CallError errorDescription not a string: %w", err)
		}
		code := CallErrorCode(codeStr)
		if !code.IsKnown() {
			// Mirror Swift behavior: unknown codes coerce to GenericError
			// rather than rejecting the frame. Logged at the call site so
			// the operator sees the original.
			code = ErrorGenericError
		}
		e.Kind = MessageTypeCallError
		e.UniqueID = uniqueID
		e.ErrorCode = code
		e.ErrorDescription = description
		if len(raw) == 5 {
			e.Payload = append(e.Payload[:0], raw[4]...)
		} else {
			e.Payload = json.RawMessage("{}")
		}
		return nil

	default:
		return fmt.Errorf("ocpp: unknown messageTypeId %d", typeRaw)
	}
}

func rawOrEmpty(p json.RawMessage) json.RawMessage {
	if len(p) == 0 {
		return json.RawMessage("{}")
	}
	return p
}
