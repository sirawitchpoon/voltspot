package ocpp

import (
	"encoding/json"
	"fmt"
	"time"
)

// Action enumerates the OCPP message actions this gateway recognises.
// Use Action.String() to send and ParseAction to decode the wire form.
type Action string

const (
	ActionAuthorize              Action = "Authorize"
	ActionBootNotification       Action = "BootNotification"
	ActionDataTransfer           Action = "DataTransfer"
	ActionHeartbeat              Action = "Heartbeat"
	ActionMeterValues            Action = "MeterValues"
	ActionStartTransaction       Action = "StartTransaction"
	ActionStatusNotification     Action = "StatusNotification"
	ActionStopTransaction        Action = "StopTransaction"
	ActionRemoteStartTransaction Action = "RemoteStartTransaction"
	ActionRemoteStopTransaction  Action = "RemoteStopTransaction"
)

// IsCSMSInitiated reports whether this action originates from the
// Central System (the Gateway), as opposed to the charge point.
// Used by the connection handler to gate which actions are accepted
// from each direction.
func (a Action) IsCSMSInitiated() bool {
	switch a {
	case ActionRemoteStartTransaction, ActionRemoteStopTransaction:
		return true
	}
	return false
}

// IsChargePointInitiated reports whether this action is sent by the
// charger to the Central System.
func (a Action) IsChargePointInitiated() bool {
	switch a {
	case ActionAuthorize,
		ActionBootNotification,
		ActionDataTransfer, // bidirectional but we only handle inbound for MVP
		ActionHeartbeat,
		ActionMeterValues,
		ActionStartTransaction,
		ActionStatusNotification,
		ActionStopTransaction:
		return true
	}
	return false
}

// ─── Shared spec enums ────────────────────────────────────────────────

// RegistrationStatus is the status the Gateway returns in
// BootNotificationResponse. Pending is valid per spec but we don't
// use it — chargers we accept are Accepted, others are Rejected.
type RegistrationStatus string

const (
	RegistrationAccepted RegistrationStatus = "Accepted"
	RegistrationPending  RegistrationStatus = "Pending"
	RegistrationRejected RegistrationStatus = "Rejected"
)

// AuthorizationStatus is the result of an Authorize / StartTransaction
// idTag check.
type AuthorizationStatus string

const (
	AuthAccepted     AuthorizationStatus = "Accepted"
	AuthBlocked      AuthorizationStatus = "Blocked"
	AuthExpired      AuthorizationStatus = "Expired"
	AuthInvalid      AuthorizationStatus = "Invalid"
	AuthConcurrentTx AuthorizationStatus = "ConcurrentTx"
)

// ChargePointErrorCode is the errorCode field on StatusNotification.
// NoError is the default value for "everything's fine".
type ChargePointErrorCode string

const (
	ErrCodeConnectorLockFailure ChargePointErrorCode = "ConnectorLockFailure"
	ErrCodeEVCommunicationError ChargePointErrorCode = "EVCommunicationError"
	ErrCodeGroundFailure        ChargePointErrorCode = "GroundFailure"
	ErrCodeHighTemperature      ChargePointErrorCode = "HighTemperature"
	ErrCodeInternalError        ChargePointErrorCode = "InternalError"
	ErrCodeLocalListConflict    ChargePointErrorCode = "LocalListConflict"
	ErrCodeNoError              ChargePointErrorCode = "NoError"
	ErrCodeOtherError           ChargePointErrorCode = "OtherError"
	ErrCodeOverCurrentFailure   ChargePointErrorCode = "OverCurrentFailure"
	ErrCodePowerMeterFailure    ChargePointErrorCode = "PowerMeterFailure"
	ErrCodePowerSwitchFailure   ChargePointErrorCode = "PowerSwitchFailure"
	ErrCodeReaderFailure        ChargePointErrorCode = "ReaderFailure"
	ErrCodeResetFailure         ChargePointErrorCode = "ResetFailure"
	ErrCodeUnderVoltage         ChargePointErrorCode = "UnderVoltage"
	ErrCodeOverVoltage          ChargePointErrorCode = "OverVoltage"
	ErrCodeWeakSignal           ChargePointErrorCode = "WeakSignal"
)

// ChargePointStatus mirrors the spec's connector state machine. Field
// names match exactly — never lowercased — so wire round-trips don't
// require translation.
type ChargePointStatus string

const (
	StatusAvailable     ChargePointStatus = "Available"
	StatusPreparing     ChargePointStatus = "Preparing"
	StatusCharging      ChargePointStatus = "Charging"
	StatusSuspendedEVSE ChargePointStatus = "SuspendedEVSE"
	StatusSuspendedEV   ChargePointStatus = "SuspendedEV"
	StatusFinishing     ChargePointStatus = "Finishing"
	StatusReserved      ChargePointStatus = "Reserved"
	StatusUnavailable   ChargePointStatus = "Unavailable"
	StatusFaulted       ChargePointStatus = "Faulted"
)

// IsKnown reports whether the status is one of the spec-defined
// values. Unknown values from a misbehaving charger are coerced to
// Unavailable by the writer so the iOS app's consumer-side rendering
// always has something safe to display.
func (s ChargePointStatus) IsKnown() bool {
	switch s {
	case StatusAvailable, StatusPreparing, StatusCharging,
		StatusSuspendedEVSE, StatusSuspendedEV, StatusFinishing,
		StatusReserved, StatusUnavailable, StatusFaulted:
		return true
	}
	return false
}

// RemoteStartStopStatus is the response Accepted/Rejected on a
// CSMS-initiated remote start/stop.
type RemoteStartStopStatus string

const (
	RemoteAccepted RemoteStartStopStatus = "Accepted"
	RemoteRejected RemoteStartStopStatus = "Rejected"
)

// DataTransferStatus is the response status for a DataTransfer call.
type DataTransferStatus string

const (
	DataTransferAccepted         DataTransferStatus = "Accepted"
	DataTransferRejected         DataTransferStatus = "Rejected"
	DataTransferUnknownMessageID DataTransferStatus = "UnknownMessageId"
	DataTransferUnknownVendorID  DataTransferStatus = "UnknownVendorId"
)

// StopReason is an optional field on StopTransaction explaining why
// the session ended.
type StopReason string

const (
	StopEmergencyStop  StopReason = "EmergencyStop"
	StopEVDisconnected StopReason = "EVDisconnected"
	StopHardReset      StopReason = "HardReset"
	StopLocal          StopReason = "Local"
	StopOther          StopReason = "Other"
	StopPowerLoss      StopReason = "PowerLoss"
	StopReboot         StopReason = "Reboot"
	StopRemote         StopReason = "Remote"
	StopSoftReset      StopReason = "SoftReset"
	StopUnlockCommand  StopReason = "UnlockCommand"
	StopDeAuthorized   StopReason = "DeAuthorized"
)

// ─── Shared structures ────────────────────────────────────────────────

// IDTagInfo is returned in Authorize / StartTransaction / StopTransaction
// responses. ExpiryDate and ParentIDTag are optional per spec.
type IDTagInfo struct {
	Status      AuthorizationStatus `json:"status"`
	ExpiryDate  *Time               `json:"expiryDate,omitempty"`
	ParentIDTag *string             `json:"parentIdTag,omitempty"`
}

// SampledValue is one reading inside a MeterValue. All fields except
// `value` are optional per spec; we don't validate the value string
// against measurand because the spec allows free-form numeric strings.
type SampledValue struct {
	Value     string  `json:"value"`
	Context   *string `json:"context,omitempty"`
	Format    *string `json:"format,omitempty"`
	Measurand *string `json:"measurand,omitempty"`
	Phase     *string `json:"phase,omitempty"`
	Location  *string `json:"location,omitempty"`
	Unit      *string `json:"unit,omitempty"`
}

// MeterValue is a timestamp + a slice of one-or-more samples.
type MeterValue struct {
	Timestamp    Time           `json:"timestamp"`
	SampledValue []SampledValue `json:"sampledValue"`
}

// Time wraps time.Time so we always (un)marshal in OCPP-J's mandatory
// ISO-8601/RFC3339 form. The default time.Time MarshalJSON is also
// RFC3339Nano which is spec-compatible, but we round to second
// precision to keep wire frames compact and stable.
type Time struct {
	time.Time
}

// Now returns the current instant rounded to the second.
func Now() Time {
	return Time{time.Now().UTC().Truncate(time.Second)}
}

// MarshalJSON emits an RFC3339 string truncated to seconds.
func (t Time) MarshalJSON() ([]byte, error) {
	return []byte(`"` + t.UTC().Format(time.RFC3339) + `"`), nil
}

// UnmarshalJSON accepts either RFC3339 or RFC3339Nano. Empty / null
// becomes zero value; the caller can distinguish via .IsZero().
func (t *Time) UnmarshalJSON(b []byte) error {
	if len(b) == 0 || string(b) == `null` || string(b) == `""` {
		t.Time = time.Time{}
		return nil
	}
	var s string
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	if s == "" {
		t.Time = time.Time{}
		return nil
	}
	parsed, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		// Try second-precision fallback for chargers that omit the
		// fractional component without a Z prefix mismatch.
		parsed, err = time.Parse(time.RFC3339, s)
		if err != nil {
			return fmt.Errorf("ocpp: invalid RFC3339 timestamp %q: %w", s, err)
		}
	}
	t.Time = parsed.UTC()
	return nil
}
