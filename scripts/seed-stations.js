#!/usr/bin/env node
/**
 * Seeds the `stations` collection in Firestore with the same six sample
 * stations that `Data/Stations/MockStationRepository.swift` carries inline.
 *
 * Why a separate script: Firestore admin writes are gated by service-account
 * credentials, not Firebase Auth, so this can't run from the iOS app. Once
 * real partner station onboarding exists this seed becomes redundant.
 *
 * Usage:
 *   1) Firebase Console → Project Settings → Service accounts → Generate
 *      new private key → save as ./service-account.json (gitignored).
 *   2) cd scripts && npm install
 *   3) node seed-stations.js [--dry-run] [--reset]
 *
 * Schema must stay in lockstep with `RealStationRepository.decode(...)`.
 * Specifically: `tariff.pricePerKWhSatang` and `tariff.sessionFeeSatang`
 * are integer satang (no Doubles for money), per CLAUDE.md.
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, GeoPoint, FieldValue } from 'firebase-admin/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SERVICE_ACCOUNT_PATH = resolve(__dirname, 'service-account.json');

const args = new Set(process.argv.slice(2));
const DRY_RUN = args.has('--dry-run');
const RESET = args.has('--reset');

// ---------------------------------------------------------------------------
// Geohash encoder — ported verbatim from Voltspot/Core/Map/Geohash.swift so
// the prefix range queries compute the same hashes both ends of the wire.
// ---------------------------------------------------------------------------
const GEOHASH_BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

function encodeGeohash(latitude, longitude, precision = 9) {
  let minLat = -90;
  let maxLat = 90;
  let minLng = -180;
  let maxLng = 180;
  let hash = '';
  let bits = 0;
  let ch = 0;
  let evenBit = true;

  while (hash.length < precision) {
    if (evenBit) {
      const mid = (minLng + maxLng) / 2;
      if (longitude >= mid) { ch = (ch << 1) | 1; minLng = mid; }
      else { ch <<= 1; maxLng = mid; }
    } else {
      const mid = (minLat + maxLat) / 2;
      if (latitude >= mid) { ch = (ch << 1) | 1; minLat = mid; }
      else { ch <<= 1; maxLat = mid; }
    }
    evenBit = !evenBit;
    bits += 1;
    if (bits === 5) {
      hash += GEOHASH_BASE32[ch];
      bits = 0;
      ch = 0;
    }
  }
  return hash;
}

// ---------------------------------------------------------------------------
// Sample stations — mirrors MockStationRepository.allSamples (six rows).
// `partnerId: 'system-seed'` flags these as platform-managed test data so a
// future migration can identify and replace them when real partners onboard.
// ---------------------------------------------------------------------------
const STATIONS = [
  {
    id: 'stn-bkk-01',
    name: 'อโศก อีวี ฮับ',
    address: 'ถ.สุขุมวิท คลองเตย กรุงเทพฯ',
    latitude: 13.7373,
    longitude: 100.5602,
    connectors: [
      { id: 'stn-bkk-01-c1', kind: 'ev', standard: 'ccs2', powerKW: 120, status: 'available' },
      { id: 'stn-bkk-01-c2', kind: 'ev', standard: 'type2', powerKW: 22, status: 'available' },
    ],
    tariff: { pricePerKWhSatang: 750, sessionFeeSatang: 0 },
    supportsDrones: false,
  },
  {
    id: 'stn-bkk-02',
    name: 'สยามพารากอน FastCharge',
    address: 'ถ.พระราม 1 ปทุมวัน กรุงเทพฯ',
    latitude: 13.7466,
    longitude: 100.5347,
    connectors: [
      { id: 'stn-bkk-02-c1', kind: 'ev', standard: 'chademo', powerKW: 50, status: 'occupied' },
      { id: 'stn-bkk-02-c2', kind: 'ev', standard: 'ccs2', powerKW: 150, status: 'available' },
    ],
    tariff: { pricePerKWhSatang: 850, sessionFeeSatang: 2000 },
    supportsDrones: false,
  },
  {
    id: 'stn-cnx-01',
    name: 'นิมมาน Charge Point',
    address: 'ถ.นิมมานเหมินทร์ เชียงใหม่',
    latitude: 18.7976,
    longitude: 98.9669,
    connectors: [
      { id: 'stn-cnx-01-c1', kind: 'ev', standard: 'type2', powerKW: 22, status: 'available' },
    ],
    tariff: { pricePerKWhSatang: 700, sessionFeeSatang: 0 },
    supportsDrones: false,
  },
  {
    id: 'stn-hkt-01',
    name: 'ป่าตอง บีช อีวี',
    address: 'ป่าตอง ภูเก็ต',
    latitude: 7.8967,
    longitude: 98.2967,
    connectors: [
      { id: 'stn-hkt-01-c1', kind: 'ev', standard: 'ccs2', powerKW: 100, status: 'available' },
    ],
    tariff: { pricePerKWhSatang: 900, sessionFeeSatang: 1000 },
    supportsDrones: false,
  },
  {
    id: 'stn-rai-01',
    name: 'ลานโดรนสุพรรณบุรี',
    address: 'ทุ่งนาสุพรรณบุรี',
    latitude: 14.4744,
    longitude: 100.1177,
    connectors: [
      { id: 'stn-rai-01-c1', kind: 'drone', standard: 'droneXT60', powerKW: 5, status: 'available' },
      { id: 'stn-rai-01-c2', kind: 'drone', standard: 'droneXT90', powerKW: 8, status: 'available' },
    ],
    tariff: { pricePerKWhSatang: 600, sessionFeeSatang: 500 },
    supportsDrones: true,
  },
  {
    id: 'stn-mix-01',
    name: 'โคราช AgriDepot ไฮบริด',
    address: 'อ.เมือง นครราชสีมา',
    latitude: 14.9799,
    longitude: 102.0978,
    connectors: [
      { id: 'stn-mix-01-c1', kind: 'ev', standard: 'ccs2', powerKW: 60, status: 'available' },
      { id: 'stn-mix-01-c2', kind: 'drone', standard: 'droneXT90', powerKW: 8, status: 'faulted' },
    ],
    tariff: { pricePerKWhSatang: 720, sessionFeeSatang: 0 },
    supportsDrones: true,
  },
];

function buildDocPayload(station) {
  const geohash = encodeGeohash(station.latitude, station.longitude);
  return {
    name: station.name,
    address: station.address,
    location: new GeoPoint(station.latitude, station.longitude),
    geohash,
    partnerId: 'system-seed',
    connectors: station.connectors,
    tariff: station.tariff,
    supportsDrones: station.supportsDrones,
    createdAt: FieldValue.serverTimestamp(),
  };
}

async function loadServiceAccount() {
  try {
    const raw = readFileSync(SERVICE_ACCOUNT_PATH, 'utf-8');
    return JSON.parse(raw);
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

async function main() {
  if (DRY_RUN) {
    console.log(`[dry-run] would seed ${STATIONS.length} stations:`);
    for (const s of STATIONS) {
      const geohash = encodeGeohash(s.latitude, s.longitude);
      console.log(`  - ${s.id}  geohash=${geohash}  (${s.latitude}, ${s.longitude})  ${s.name}`);
    }
    return;
  }

  const serviceAccount = await loadServiceAccount();
  const projectId = serviceAccount.project_id;
  initializeApp({ credential: cert(serviceAccount), projectId });
  const db = getFirestore();
  console.log(`Connected to project "${projectId}".`);

  if (RESET) {
    console.log('Deleting existing seed stations…');
    const snap = await db.collection('stations').where('partnerId', '==', 'system-seed').get();
    if (!snap.empty) {
      const batch = db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      console.log(`  ✓ deleted ${snap.size} doc(s)`);
    }
  }

  console.log(`Seeding ${STATIONS.length} stations into project "${projectId}"…`);
  const batch = db.batch();
  for (const s of STATIONS) {
    const ref = db.collection('stations').doc(s.id);
    batch.set(ref, buildDocPayload(s), { merge: true });
  }
  await batch.commit();

  for (const s of STATIONS) {
    const geohash = encodeGeohash(s.latitude, s.longitude);
    console.log(`  ✓ ${s.id.padEnd(14)} geohash=${geohash}  ${s.name}`);
  }
  console.log('Done.');
}

main().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
