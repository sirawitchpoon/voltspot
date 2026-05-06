package ocpp

// Messages in this file are charge point → Central System Calls. Field
// names + required/optional must match the JSON schemas under
// OCPP_1.6_documentation_2019_12/schemas/json/ exactly, and must mirror
// the iOS Codable structs in Voltspot/Data/OCPP/Models/*.swift.
//
// Convention: required fields are non-pointer, optional fields are
// pointer types with `omitempty`. This keeps zero values from leaking
// onto the wire (e.g. a missing `info` would otherwise become `""`).

// ─── BootNotification ─────────────────────────────────────────────────
// Schema: BootNotification.json — required: chargePointVendor,
// chargePointModel.

type BootNotificationRequest struct {
	ChargePointVendor       string  `json:"chargePointVendor"`
	ChargePointModel        string  `json:"chargePointModel"`
	ChargePointSerialNumber *string `json:"chargePointSerialNumber,omitempty"`
	ChargeBoxSerialNumber   *string `json:"chargeBoxSerialNumber,omitempty"`
	FirmwareVersion         *string `json:"firmwareVersion,omitempty"`
	ICCID                   *string `json:"iccid,omitempty"`
	IMSI                    *string `json:"imsi,omitempty"`
	MeterType               *string `json:"meterType,omitempty"`
	MeterSerialNumber       *string `json:"meterSerialNumber,omitempty"`
}

// BootNotificationResponse — all three fields are required per schema.
type BootNotificationResponse struct {
	Status      RegistrationStatus `json:"status"`
	CurrentTime Time               `json:"currentTime"`
	Interval    int                `json:"interval"`
}

// ─── Heartbeat ────────────────────────────────────────────────────────
// Empty payload — modeled as a struct so the JSON form is `{}`, not
// `null`. Spec section 5.6.

type HeartbeatRequest struct{}

type HeartbeatResponse struct {
	CurrentTime Time `json:"currentTime"`
}

// ─── StatusNotification ───────────────────────────────────────────────
// Schema: StatusNotification.json — required: connectorId, errorCode,
// status. Connector 0 means the charger as a whole, not any single
// EVSE — handle that in the writer.

type StatusNotificationRequest struct {
	ConnectorID     int                  `json:"connectorId"`
	ErrorCode       ChargePointErrorCode `json:"errorCode"`
	Status          ChargePointStatus    `json:"status"`
	Info            *string              `json:"info,omitempty"`
	Timestamp       *Time                `json:"timestamp,omitempty"`
	VendorID        *string              `json:"vendorId,omitempty"`
	VendorErrorCode *string              `json:"vendorErrorCode,omitempty"`
}

type StatusNotificationResponse struct{}

// ─── Authorize ────────────────────────────────────────────────────────
// Schema: Authorize.json — required: idTag.

type AuthorizeRequest struct {
	IDTag string `json:"idTag"`
}

type AuthorizeResponse struct {
	IDTagInfo IDTagInfo `json:"idTagInfo"`
}

// ─── StartTransaction ─────────────────────────────────────────────────
// Schema: StartTransaction.json — required: connectorId, idTag,
// meterStart, timestamp.

type StartTransactionRequest struct {
	ConnectorID   int    `json:"connectorId"`
	IDTag         string `json:"idTag"`
	MeterStart    int    `json:"meterStart"` // Wh
	ReservationID *int   `json:"reservationId,omitempty"`
	Timestamp     Time   `json:"timestamp"`
}

type StartTransactionResponse struct {
	IDTagInfo     IDTagInfo `json:"idTagInfo"`
	TransactionID int       `json:"transactionId"`
}

// ─── StopTransaction ──────────────────────────────────────────────────
// Schema: StopTransaction.json — required: meterStop, timestamp,
// transactionId. idTag is optional because the charger may stop the
// session without re-authorizing (e.g. EmergencyStop).

type StopTransactionRequest struct {
	IDTag           *string      `json:"idTag,omitempty"`
	MeterStop       int          `json:"meterStop"` // Wh
	Timestamp       Time         `json:"timestamp"`
	TransactionID   int          `json:"transactionId"`
	Reason          *StopReason  `json:"reason,omitempty"`
	TransactionData []MeterValue `json:"transactionData,omitempty"`
}

type StopTransactionResponse struct {
	IDTagInfo *IDTagInfo `json:"idTagInfo,omitempty"`
}

// ─── MeterValues ──────────────────────────────────────────────────────
// Schema: MeterValues.json — required: connectorId, meterValue.
// transactionId is optional because chargers can send periodic
// out-of-session readings.

type MeterValuesRequest struct {
	ConnectorID   int          `json:"connectorId"`
	TransactionID *int         `json:"transactionId,omitempty"`
	MeterValue    []MeterValue `json:"meterValue"`
}

type MeterValuesResponse struct{}

// ─── DataTransfer ─────────────────────────────────────────────────────
// Schema: DataTransfer.json. Vendor-specific extension; we accept,
// log, and respond with UnknownVendorId unless an integration handles
// it. The iOS-side Swift struct allows only a `data` string, but the
// schema allows any JSON value — keep our field a string for now and
// promote to json.RawMessage if a real vendor needs richer payload.

type DataTransferRequest struct {
	VendorID  string  `json:"vendorId"`
	MessageID *string `json:"messageId,omitempty"`
	Data      *string `json:"data,omitempty"`
}

type DataTransferResponse struct {
	Status DataTransferStatus `json:"status"`
	Data   *string            `json:"data,omitempty"`
}
