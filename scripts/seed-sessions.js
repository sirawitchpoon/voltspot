#!/usr/bin/env node
/**
 * Seeds the `sessions` collection with synthetic completed charging
 * sessions across the partner's claimed stations so the Partner-side
 * Dashboard / Earnings / MyStations screens show realistic numbers
 * during pitch demos.
 *
 * The script is deliberately lossy: it is NOT a substitute for real
 * OCPP traffic flowing through the Gateway, it just lets the UI
 * surface aggregate numbers when no real chargers are wired up yet.
 * Every doc it writes carries `userId === 'demo-consumer-001'` and
 * `seedSource === 'demo'` so `--reset` can find and delete them
 * without touching real sessions.
 *
 * Usage:
 *   1) Make sure scripts/service-account.json is in place (same
 *      Firebase Admin key the other scripts use).
 *   2) cd scripts && node seed-sessions.js <partner-uid>
 *
 * Flags:
 *   --dry-run      preview without writing
 *   --reset        delete prior demo sessions (userId == 'demo-consumer-001')
 *                  before seeding — idempotent re-runs
 *   --days=N       window size in days (default 30)
 *   --sessions=N   target session count (default 150)
 *   --today=N      sessions concentrated in the past 8 hours (default 8)
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SERVICE_ACCOUNT_PATH = resolve(__dirname, 'service-account.json');

const argv = process.argv.slice(2);
const flags = new Set(argv.filter((a) => a.startsWith('--') && !a.includes('=')));
const positional = argv.filter((a) => !a.startsWith('-'));

const DRY_RUN = flags.has('--dry-run');
const RESET = flags.has('--reset');
const flagValue = (name, fallback) => {
  const hit = argv.find((a) => a.startsWith(`--${name}=`));
  if (!hit) return fallback;
  const n = Number(hit.slice(`--${name}=`.length));
  return Number.isFinite(n) && n > 0 ? n : fallback;
};
const DAYS = flagValue('days', 30);
const TARGET_TOTAL = flagValue('sessions', 150);
const TODAY_COUNT = flagValue('today', 8);

const PARTNER_UID = positional[0];
const DEMO_CONSUMER_UID = 'demo-consumer-001';

if (!PARTNER_UID) {
  console.error(
    'Usage: node seed-sessions.js <partner-uid> [--dry-run] [--reset]\n' +
    '       [--days=30] [--sessions=150] [--today=8]'
  );
  process.exit(1);
}

// Per-station traffic weights — Bangkok stations get the lion's share
// because that's where the user's pitch geo focuses; drone field is
// quiet because most fleets aren't deployed yet. The numbers don't
// have to add to anything in particular, they're relative weights.
const STATION_WEIGHTS = {
  'stn-bkk-01': 5, // Asoke EV Hub — high traffic, premium location
  'stn-bkk-02': 5, // Siam Paragon FastCharge — premium retail
  'stn-cnx-01': 3, // Nimman — Chiang Mai tourist
  'stn-hkt-01': 3, // Patong — Phuket tourist
  'stn-mix-01': 2, // Korat AgriDepot Hybrid — secondary city
  'stn-rai-01': 1, // Suphanburi Drone Field — niche
};

async function loadServiceAccount() {
  try {
    return JSON.parse(readFileSync(SERVICE_ACCOUNT_PATH, 'utf-8'));
  } catch (err) {
    if (err.code === 'ENOENT') {
      console.error(
        '\n❌ service-account.json not found.\n' +
        '   Firebase Console → ⚙️  Project Settings → Service accounts →\n' +
        '   "Generate new private key" → save as scripts/service-account.json\n'
      );
    } else {
      console.error('Failed to read service-account.json:', err.message);
    }
    process.exit(1);
  }
}

/// Returns a Date inside the last `days` window. ~80% of sessions
/// are weighted toward business hours (08:00-22:00) so the daily
/// chart looks alive instead of uniformly noisy.
function randomStartInWindow(days) {
  const now = Date.now();
  const offsetMs = Math.random() * days * 24 * 60 * 60 * 1000;
  const start = new Date(now - offsetMs);
  // Snap 80% of timestamps into 08:00-22:00 local; leave 20% as
  // overnight noise (apartment trickle charging).
  if (Math.random() < 0.8) {
    const hour = 8 + Math.floor(Math.random() * 14); // 8..21
    start.setHours(hour, Math.floor(Math.random() * 60), Math.floor(Math.random() * 60), 0);
  }
  return start;
}

function randomStartToday() {
  // Anchor to the start of the local day so every "today" session
  // lands inside the same calendar day the iOS app's
  // `Calendar.current.startOfDay(for: Date())` will compute. The
  // earlier "last 8 hours" implementation walked past midnight when
  // the seeder happened to run shortly after 00:00 and all the
  // would-be "today" rows ended up tagged as yesterday.
  const now = new Date();
  const startOfToday = new Date(now);
  startOfToday.setHours(0, 0, 0, 0);
  const elapsedMs = Math.max(1, now.getTime() - startOfToday.getTime());
  const offsetMs = Math.floor(Math.random() * elapsedMs);
  return new Date(startOfToday.getTime() + offsetMs);
}

/// Banker's-rounded satang cost — mirrors the Go gateway's pricing
/// math so the demo numbers stay believable.
function computeCostSatang(energyKWh, tariff) {
  const perKWh = tariff?.pricePerKWhSatang ?? 700;
  const sessionFee = tariff?.sessionFeeSatang ?? 0;
  const variable = Math.round(energyKWh * perKWh);
  return variable + sessionFee;
}

function pickWeighted(weights) {
  const entries = Object.entries(weights);
  const total = entries.reduce((s, [, w]) => s + w, 0);
  let roll = Math.random() * total;
  for (const [id, w] of entries) {
    if ((roll -= w) <= 0) return id;
  }
  return entries[0][0];
}

function buildSession({ stationId, station, startedAt, txCounter }) {
  // Realistic charge curves — drone connectors top out lower because
  // batteries are smaller; EV connectors swing wider depending on
  // whether the driver topped up or did a full session.
  const isDrone = station.supportsDrones && (station.connectors?.[0]?.kind === 'drone');
  const energyKWh = isDrone
    ? +(2 + Math.random() * 6).toFixed(2)       // 2-8 kWh
    : +(15 + Math.random() * 35).toFixed(2);    // 15-50 kWh
  const durationMin = isDrone
    ? 15 + Math.floor(Math.random() * 30)
    : 30 + Math.floor(Math.random() * 60);

  const endedAt = new Date(startedAt.getTime() + durationMin * 60 * 1000);
  const costSatang = computeCostSatang(energyKWh, station.tariff);
  const connectorId = station.connectors?.[0]?.id ?? `${stationId}-c1`;

  return {
    id: `tx-demo-${txCounter}`,
    payload: {
      userId: DEMO_CONSUMER_UID,
      // Denormalised from /stations/{id}.partnerId so the Firestore
      // security rule can authorise partner reads via a single-doc
      // check instead of a cross-collection join.
      partnerId: station.partnerId ?? PARTNER_UID,
      stationId,
      connectorId,
      startTime: Timestamp.fromDate(startedAt),
      endTime: Timestamp.fromDate(endedAt),
      energyKWh,
      costSatang,
      status: 'completed',
      ocppTransactionId: txCounter,
      seedSource: 'demo',
    },
  };
}

async function main() {
  const serviceAccount = await loadServiceAccount();
  const projectId = serviceAccount.project_id;
  initializeApp({ credential: cert(serviceAccount), projectId });
  const db = getFirestore();
  console.log(`Connected to project "${projectId}".`);

  const stationsSnap = await db
    .collection('stations')
    .where('partnerId', '==', PARTNER_UID)
    .get();

  if (stationsSnap.empty) {
    console.error(
      `No stations found with partnerId == "${PARTNER_UID}".\n` +
      `Run claim-stations.js first to assign sample stations to this uid.`
    );
    process.exit(1);
  }

  const stations = {};
  stationsSnap.docs.forEach((d) => {
    stations[d.id] = d.data();
  });
  console.log(`Found ${Object.keys(stations).length} owned stations.`);

  // Filter the weights table down to stations we actually own — falls
  // back to uniform weights if a partner has stations outside the
  // canonical six.
  const weights = {};
  for (const id of Object.keys(stations)) {
    weights[id] = STATION_WEIGHTS[id] ?? 2;
  }

  if (RESET) {
    console.log(`Deleting prior demo sessions (userId == "${DEMO_CONSUMER_UID}")…`);
    const prior = await db
      .collection('sessions')
      .where('userId', '==', DEMO_CONSUMER_UID)
      .get();
    if (!prior.empty) {
      // Firestore deletes max 500 per batch.
      let count = 0;
      for (let i = 0; i < prior.docs.length; i += 500) {
        const batch = db.batch();
        prior.docs.slice(i, i + 500).forEach((d) => batch.delete(d.ref));
        await batch.commit();
        count += Math.min(500, prior.docs.length - i);
      }
      console.log(`  ✓ deleted ${count} doc(s)`);
    } else {
      console.log('  (none to delete)');
    }
  }

  const historicalCount = Math.max(0, TARGET_TOTAL - TODAY_COUNT);
  const sessions = [];
  let counter = Date.now() % 1_000_000;

  for (let i = 0; i < historicalCount; i++) {
    const stationId = pickWeighted(weights);
    sessions.push(
      buildSession({
        stationId,
        station: stations[stationId],
        startedAt: randomStartInWindow(DAYS),
        txCounter: counter++,
      })
    );
  }
  for (let i = 0; i < TODAY_COUNT; i++) {
    const stationId = pickWeighted(weights);
    sessions.push(
      buildSession({
        stationId,
        station: stations[stationId],
        startedAt: randomStartToday(),
        txCounter: counter++,
      })
    );
  }

  // Summary
  const totalSatang = sessions.reduce((s, x) => s + x.payload.costSatang, 0);
  const totalKWh = sessions.reduce((s, x) => s + x.payload.energyKWh, 0);
  const perStation = {};
  sessions.forEach((s) => {
    const id = s.payload.stationId;
    perStation[id] = (perStation[id] ?? 0) + 1;
  });

  console.log(
    `\nPlan: ${sessions.length} sessions  ·  ` +
    `${totalKWh.toFixed(1)} kWh total  ·  ` +
    `฿${(totalSatang / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} gross`
  );
  Object.entries(perStation)
    .sort(([, a], [, b]) => b - a)
    .forEach(([id, n]) => {
      console.log(`  · ${id.padEnd(14)} ${String(n).padStart(3)} sessions`);
    });

  if (DRY_RUN) {
    console.log('\n[dry-run] no writes performed.');
    return;
  }

  console.log(`\nWriting ${sessions.length} sessions to /sessions…`);
  for (let i = 0; i < sessions.length; i += 500) {
    const batch = db.batch();
    sessions.slice(i, i + 500).forEach((s) => {
      const ref = db.collection('sessions').doc(s.id);
      batch.set(ref, s.payload);
    });
    await batch.commit();
  }
  console.log('Done.');
}

main().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
