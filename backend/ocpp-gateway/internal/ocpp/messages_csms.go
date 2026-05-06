package ocpp

// Messages in this file are Central System (Gateway) → charge point
// Calls. Used by REST handlers when the iOS app initiates a remote
// session start or stop.

// ─── RemoteStartTransaction ───────────────────────────────────────────
// Schema: RemoteStartTransaction.json — required: idTag.
//
// chargingProfile is intentionally omitted from this scaffold — it's
// a large nested structure used for demand-response scheduling. Add
// it when partner UI needs to send/inspect smart-charging profiles.
// The same omission exists on the iOS side (see
// Voltspot/Data/OCPP/Models/RemoteStartTransaction.swift).

type RemoteStartTransactionRequest struct {
	ConnectorID *int   `json:"connectorId,omitempty"`
	IDTag       string `json:"idTag"`
}

type RemoteStartTransactionResponse struct {
	Status RemoteStartStopStatus `json:"status"`
}

// ─── RemoteStopTransaction ────────────────────────────────────────────
// Schema: RemoteStopTransaction.json — required: transactionId.

type RemoteStopTransactionRequest struct {
	TransactionID int `json:"transactionId"`
}

type RemoteStopTransactionResponse struct {
	Status RemoteStartStopStatus `json:"status"`
}
