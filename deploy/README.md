# Voltspot Firebase Deploy

Source of truth for **Firestore security rules + indexes**. Deployed via the
Firebase CLI from this directory.

## Prerequisites

```bash
npm install -g firebase-tools
firebase login
```

The Firebase project must be created in the Firebase Console first
(asia-southeast1, Native mode Firestore). After creation, set the active
project:

```bash
cd deploy
firebase use --add   # pick the Voltspot project, alias "default"
```

## Deploy

```bash
cd deploy

# Rules only
firebase deploy --only firestore:rules

# Indexes only (composite indexes; first deploy can take 1-5 min to build)
firebase deploy --only firestore:indexes

# Both
firebase deploy --only firestore
```

## Schema Summary

| Collection | Owner | Reader |
|---|---|---|
| `users/{uid}` | the user | the user |
| `partners/{uid}` | the partner | the partner |
| `stations/{id}` | partnerId or Gateway | any signed-in user |
| `sessions/{id}` | Gateway | session.userId |
| `connector_status/{stationId}_{connectorId}` | Gateway | any signed-in user |

`isGatewayServiceAccount()` checks for a custom Firebase token with
`token.role == 'gateway'`. The OCPP Gateway service mints these via the
Admin SDK on Cloud Run startup.

## Money Invariant

`tariff.pricePerKWhSatang`, `tariff.sessionFeeSatang`, and
`session.costSatang` are stored as **integer satang** (1 baht = 100 satang).
Never write `Double` for money fields — see CLAUDE.md.
