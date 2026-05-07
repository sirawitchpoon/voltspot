# Voltspot OCPP Gateway

Go service that hosts persistent WebSocket connections from EV
chargers and exposes a small REST API for the iOS app to issue
remote start/stop commands. Production target: **Google Cloud Run**
in `asia-southeast1`.

## What it does

```
                  ┌──────────────────────────────────┐
                  │  Voltspot iOS app                │
                  └──────┬───────────────────────────┘
                         │ Bearer <Firebase ID token>
                         │ POST /api/.../remote-start
                         ▼
┌─────────────────────────────────────────────────┐
│  ocpp-gateway   ── /healthz, /readyz             │
│                 ── /api/...    (REST, auth-gated)│
│                 ── /ocpp/{cp}  (WebSocket, OCPP) │
└─────────────────────────────────────────────────┘
                         │ wss:// + Sec-WebSocket-Protocol: ocpp1.6
                         ▼
                  ┌──────────────────────────────────┐
                  │  Charge points (1.6-J)           │
                  └──────────────────────────────────┘
                         │
                         ▼ Firestore admin writes
              /sessions/{id}, /connector_status/{...}
```

The Gateway is **stateful** — it owns the WebSocket connections —
which is why it runs on Cloud Run with `min-instances=1` and CPU
always allocated, not on Cloud Functions.

## Layout

```
backend/ocpp-gateway/
├── cmd/gateway/        # main + middleware
├── internal/ocpp/      # wire envelope + 10 message types
├── internal/server/    # Hub, Conn, WS handler, REST, delegate, health
├── internal/auth/      # Firebase ID token middleware
├── internal/firestore/ # writes to /sessions, /connector_status
├── internal/pricing/   # session cost calc (Int satang only)
├── internal/transactions/ # OCPP transactionId allocator
├── Dockerfile          # multi-stage, distroless static-debian:nonroot
├── cloudbuild.yaml     # Cloud Build → Artifact Registry → Cloud Run
└── README.md           # this file
```

## Environment

| Var | Required | Default | Purpose |
|---|---|---|---|
| `FIREBASE_PROJECT_ID` | yes | — | Firebase project to verify ID tokens against and write Firestore docs into |
| `GOOGLE_APPLICATION_CREDENTIALS` | local only | — | Path to service-account JSON. On Cloud Run, ADC handles this — leave unset. |
| `PORT` | — | `8080` | HTTP listen port (Cloud Run injects) |
| `LOG_LEVEL` | — | `info` | One of `debug` / `info` / `warn` / `error` |
| `CHARGER_IDLE_AFTER` | — | `10m` | Close connections silent for longer than this |
| `IDLE_SWEEP_INTERVAL` | — | `2m` | How often to scan for idle connections |
| `CALL_TIMEOUT` | — | `30s` | Per-Call timeout (charger → gateway round-trip) |
| `REST_CALL_TIMEOUT` | — | `10s` | iOS REST → charger round-trip cap |
| `SHUTDOWN_TIMEOUT` | — | `25s` | Time to drain connections on SIGTERM |
| `CORS_ALLOWED_ORIGINS` | — | (none) | Comma-separated list. Real chargers don't need this; useful for browser test clients. |

## Running locally

```bash
# Pre-req: Firebase service account JSON saved somewhere safe.
# Recommended: scripts/service-account.json (already gitignored).
export FIREBASE_PROJECT_ID=voltspot-e410c
export GOOGLE_APPLICATION_CREDENTIALS=$PWD/../../scripts/service-account.json

go run ./cmd/gateway
```

The server logs JSON to stdout (Cloud Logging compatible). Hit
`http://localhost:8080/healthz` to confirm it's up; `/readyz`
returns 503 until startup completes.

### Smoke-testing OCPP

```bash
# wscat speaks WebSocket and lets you paste raw frames.
brew install wscat   # or npm i -g wscat

wscat -c ws://localhost:8080/ocpp/test-charger \
      --subprotocol ocpp1.6

# Paste an OCPP-J BootNotification Call:
[2,"abc-123","BootNotification",{"chargePointVendor":"WallboxCo","chargePointModel":"WB1"}]
```

Expected reply:

```json
[3,"abc-123",{"status":"Accepted","currentTime":"2026-05-...Z","interval":300}]
```

A `/connector_status/test-charger_0` doc should also appear in
Firestore Console.

### Issuing remote start from a REST client

```bash
# Get a fresh Firebase ID token from the iOS app (Auth.auth().currentUser?.getIDToken())
# or from Firebase Console → Authentication → Users → ⋮ → Generate ID token
TOKEN=eyJ...

curl -X POST http://localhost:8080/api/stations/test-charger/connectors/1/remote-start \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"idTag":"voltspot-test"}'
```

Returns 202 + `{"status":"Accepted",...}` on success; 409 if the
charger rejected; 503 if the charger isn't online; 504 if the call
timed out.

## Tests

### Unit tests

```bash
go test -race ./...
```

Cover the envelope codec, the Firebase ID token middleware (with a
fake Verifier), pricing math, the transaction-id allocator
(including concurrency), and the pending-starts registry.

### Smoke tests — checked-in, runnable, single-screenshot proof

Two end-to-end smoke runners ship as Go binaries under `cmd/`. Each
prints a colored `PASS` / `FAIL` per scenario and exits non-zero on
any failure — designed so a single screenshot tells the whole story.

**Phase A — Firebase backend** (no gateway needed)

Verifies what the iOS app depends on: Identity Toolkit signup, ID
token verification, stations seed integrity (count, integer satang,
9-char Thailand geohash), and three Firestore security rules
(authenticated read, anonymous denied, cross-user write denied).

```bash
export FIREBASE_PROJECT_ID=voltspot-e410c
export GOOGLE_APPLICATION_CREDENTIALS=$PWD/../../scripts/service-account.json

go run ./cmd/smoke-app
```

The Web API key is read from `../../Voltspot/Resources/GoogleService-Info.plist`
unless `-api-key` or `VOLTSPOT_FIREBASE_API_KEY` is set. Two
ephemeral test users (`smoke-a-{ts}@voltspot.test`,
`smoke-b-{ts}@voltspot.test`) are created and deleted automatically
unless `-cleanup=false`.

**Phase B — OCPP Gateway** (requires `go run ./cmd/gateway` running)

Connects as a fake charger over WebSocket and exercises the full
session lifecycle (Boot → StatusNotification → Heartbeat →
StartTransaction → MeterValues → StopTransaction), then optionally
verifies the resulting `/connector_status` and `/sessions` docs in
Firestore.

```bash
# In one terminal, start the gateway:
go run ./cmd/gateway

# In another terminal, run the smoke:
go run ./cmd/smoke -firestore                          # full check
go run ./cmd/smoke                                     # wire-only, fast
go run ./cmd/smoke -firestore -cleanup                 # also delete created docs
go run ./cmd/smoke -url wss://staging.run.app/ocpp/cp  # against a deployed gateway
```

Both smoke runners exit with code 0 on full pass, 1 on any failure
— wire them into a deployment pipeline gate when the gateway is
reachable from the runner.

## Deploying

The `cloudbuild.yaml` pipeline is wired to run on push to `main` —
**but** the Cloud Build trigger needs to be created manually first
(one-off):

1. Cloud Build Console → Triggers → Create.
2. Source: connect the GitHub repo.
3. Path filter: `backend/ocpp-gateway/**`.
4. Substitutions: `_REGION=asia-southeast1`, `_SERVICE=voltspot-ocpp-gateway`, `_AR_REPO=voltspot`, `_FIREBASE_PROJECT_ID=voltspot-e410c`.
5. Service account: grant `Cloud Run Admin`, `Service Account User`, `Artifact Registry Writer`.

After the first manual deploy succeeds, every subsequent push to
`main` that touches the Gateway folder builds, tests, and rolls out
automatically. Roll back via `gcloud run services rollback`.

## Architecture decisions

- **WebSocket lib**: `github.com/coder/websocket` — modern, context-
  aware, smaller dependency footprint than `gorilla/websocket`. Both
  are mature; coder/ wins on async API ergonomics.
- **No goroutine pool**: each Conn owns a read goroutine + a write
  goroutine + one short-lived goroutine per inbound Call. Fine up to
  ~10K chargers per instance; revisit if profiling shows contention.
- **Money is `int64` satang**: never `float64`. Mirrors the iOS
  invariant in `CLAUDE.md`. The pricing package rounds half-to-even
  so aggregated revenue across many sessions is fair.
- **Transaction IDs are monotonic in-process** (with a Firestore
  high-water-mark seed at startup). For multi-instance deploys
  switch to a `/counters/transactions` doc with `FieldValue.Increment`.
- **Authorize is permissive in MVP** — any non-empty idTag is
  Accepted. Enforce real-RFID lookup in the followup PR that lands
  the `/idtags/{idTag}` collection.
- **OCPP unknown error codes** coerce to `GenericError` on inbound
  decode (mirrors Swift). Original code is logged.
- **Reconnect handover**: when a charger reconnects with the same
  identity, the old Conn is closed and replaced; in-flight Calls on
  the old Conn return `ErrConnectionClosed`.

## What's not done yet

- No tests for `internal/server/conn.go` interactions — needs a
  mock WebSocket that drives the read pump. Reasonable next addition.
- No metrics export. Cloud Run captures CPU + memory + request
  count automatically; bespoke OCPP metrics (active sessions, failed
  Authorize ratio) need OpenTelemetry wiring later.
- App Check enforcement is not turned on yet. Plumb the verifier in
  once Firebase App Check is enabled in the console.
- DataTransfer always returns `UnknownVendorId`. Add a vendor
  registry when a real partner integration needs it.
- `userId` on `/sessions/{id}` is currently empty — populated by the
  REST handler when the iOS app initiates RemoteStart, but charger-
  initiated StartTransaction has no link from idTag → uid yet. Add
  when `/idtags/{idTag}.userId` is populated.
