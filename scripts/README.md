# Voltspot Operational Scripts

Node.js scripts that run **outside** the iOS app — seeding test data,
data migrations, batch exports. Authenticate via Firebase Admin SDK
service-account credentials, not user auth.

## Setup (one-time)

1. **Generate a service account key** in the Firebase Console:
   - ⚙️ Project Settings → **Service accounts** tab
   - "Generate new private key" → confirm
   - Save the downloaded JSON as **`scripts/service-account.json`**
2. **Install dependencies:**
   ```bash
   cd scripts
   npm install
   ```

⚠️ **`service-account.json` is project-level admin** — bypasses every
Firestore security rule. Treat it like a root password:
- Already gitignored (`*service-account*.json`)
- Never paste into chat / email / Slack
- Rotate immediately if leaked (Firebase Console → Service accounts → revoke)

## Available scripts

### `seed-stations.js` — populate the `stations` collection

Mirrors `MockStationRepository.allSamples` (six rows across Bangkok,
Chiang Mai, Phuket, Suphanburi, Korat) into Firestore so
`StationFinderView` and `MyStationsView` show real data instead of an
empty map.

```bash
# Preview without writing:
node seed-stations.js --dry-run

# Write/update (uses set with merge — safe to re-run):
node seed-stations.js

# Reset: delete existing system-seed stations first, then re-write:
node seed-stations.js --reset
```

Each doc gets:
- `name`, `address`, `location` (GeoPoint), `geohash`, `connectors[]`,
  `tariff` (Int satang), `supportsDrones`, `partnerId: "system-seed"`,
  `createdAt`.

The geohash is computed with the same algorithm as
`Voltspot/Core/Map/Geohash.swift`, so the iOS prefix-range query lines up.

## Adding a new script

Drop a `*.js` file in this folder, add a corresponding `npm run` entry
in `package.json` if it'll be run frequently, and document the script
section in this README so it's discoverable.

Schema-touching scripts must reference the Swift type they mirror
(`Domain/Entities/*.swift`) and stay in lockstep — call this out in the
script header so the next person doesn't drift.
