#!/usr/bin/env node
/**
 * Updates only the `name` and `address` fields on the seed stations,
 * leaving everything else (most importantly `partnerId`) intact.
 *
 * Why a separate script instead of re-running seed-stations.js: the
 * seeder writes `partnerId: 'system-seed'` as part of its payload, so
 * a merge-set after a partner has claimed the docs would un-claim
 * them. This script touches a deliberately narrow field set.
 *
 * Usage:
 *   cd scripts && node rename-stations.js [--dry-run]
 *
 * The mapping below is hardcoded to match the six demo stations from
 * `seed-stations.js`. Add a new entry here whenever a station gets a
 * Thai-localised display string for the pitch demo.
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SERVICE_ACCOUNT_PATH = resolve(__dirname, 'service-account.json');
const DRY_RUN = process.argv.includes('--dry-run');

const RENAMES = {
  'stn-bkk-01': { name: 'อโศก อีวี ฮับ',           address: 'ถ.สุขุมวิท คลองเตย กรุงเทพฯ' },
  'stn-bkk-02': { name: 'สยามพารากอน FastCharge', address: 'ถ.พระราม 1 ปทุมวัน กรุงเทพฯ' },
  'stn-cnx-01': { name: 'นิมมาน Charge Point',     address: 'ถ.นิมมานเหมินทร์ เชียงใหม่' },
  'stn-hkt-01': { name: 'ป่าตอง บีช อีวี',          address: 'ป่าตอง ภูเก็ต' },
  'stn-rai-01': { name: 'ลานโดรนสุพรรณบุรี',       address: 'ทุ่งนาสุพรรณบุรี' },
  'stn-mix-01': { name: 'โคราช AgriDepot ไฮบริด',  address: 'อ.เมือง นครราชสีมา' },
};

async function loadServiceAccount() {
  try {
    return JSON.parse(readFileSync(SERVICE_ACCOUNT_PATH, 'utf-8'));
  } catch (err) {
    console.error('Failed to read service-account.json:', err.message);
    process.exit(1);
  }
}

async function main() {
  const serviceAccount = await loadServiceAccount();
  initializeApp({ credential: cert(serviceAccount), projectId: serviceAccount.project_id });
  const db = getFirestore();

  console.log(`Connected to project "${serviceAccount.project_id}".`);
  console.log(`Renaming ${Object.keys(RENAMES).length} stations…`);

  if (DRY_RUN) {
    for (const [id, fields] of Object.entries(RENAMES)) {
      console.log(`[dry-run] ${id.padEnd(14)} → "${fields.name}"`);
    }
    return;
  }

  const batch = db.batch();
  for (const [id, fields] of Object.entries(RENAMES)) {
    batch.update(db.collection('stations').doc(id), fields);
  }
  await batch.commit();

  for (const [id, fields] of Object.entries(RENAMES)) {
    console.log(`  ✓ ${id.padEnd(14)} → "${fields.name}"`);
  }
  console.log('Done.');
}

main().catch((err) => {
  console.error('Rename failed:', err);
  process.exit(1);
});
