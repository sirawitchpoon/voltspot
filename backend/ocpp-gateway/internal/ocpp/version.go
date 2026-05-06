// Package ocpp implements OCPP 1.6-J wire types and envelope handling.
//
// The shapes here mirror the iOS app's Swift models in
// Voltspot/Data/OCPP/Models/*.swift bit-for-bit so iOS clients (when
// they speak to the Gateway directly for diagnostics) and chargers
// agree on the wire format. JSON schemas under
// OCPP_1.6_documentation_2019_12/schemas/json/ are the source of
// truth — required vs optional fields and field name casing match
// those schemas exactly.
package ocpp

// Version identifies the OCPP protocol version negotiated with the
// charger. We only support 1.6-J for now; 2.0.1 would add a parallel
// constant + parallel message types.
const Version = "1.6"

// SubprotocolHeader is the value the Gateway requires on the
// Sec-WebSocket-Protocol HTTP header during the WebSocket handshake.
// Charge points that don't include this header speak a different
// protocol and must be rejected at the upgrade step (OCPP-J spec
// §3.1.3.1).
const SubprotocolHeader = "ocpp1.6"

// HeartbeatIntervalSeconds is the default interval the Gateway tells
// the charger to use when responding to BootNotification. Five
// minutes balances bandwidth against detecting silent disconnects;
// chargers that boot more often than this are usually misconfigured.
const HeartbeatIntervalSeconds = 300
