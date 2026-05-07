#!/usr/bin/env node
/**
 * Re-assigns the seed stations (those with `partnerId === 'system-seed'`)
 * to a real Firebase Auth uid so the signed-in partner sees them on
 * MyStations / Earnings / Dashboard.
 *
 * The seed script (`seed-stations.js`) marks every sample doc with
 * `partnerId: 'system-seed'` as a sentinel — that lets us find them
 * later and rewrite the field without touching anything a real
 * partner has uploaded. Running this script does NOT delete any data,
 * it only updates `partnerId` (and a `claimedAt` audit timestamp).
 *
 * Usage:
 *   1) Find the partner uid:
 *      Firebase Console → Authentication → Users → copy the UID
 *   2) cd scripts && node claim-stations.js <uid>
 *
 * Flags:
 *   --dry-run        list the docs that would change without writing
 *   --revert         set partnerId back to 'system-seed' (un-claims)
 *   --from=<filter>  only claim stations currently owned by this uid
 *                    instead of the default 'system-seed' (use to
 *                    transfer between partners)
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SERVICE_ACCOUNT_PATH = resolve(__dirname, 'service-account.json');

const argv = process.argv.slice(2);
const flags = new Set(argv.filter((a) => a.startsWith('-')));
const positional = argv.filter((a) => !a.startsWith('-'));

const DRY_RUN = flags.has('--dry-run');
const REVERT = flags.has('--revert');
const FROM_FLAG = argv.find((a) => a.startsWith('--from='));
const FROM = FROM_FLAG ? FROM_FLAG.slice('--from='.length) : 'system-seed';

const TARGET_UID = positional[0];

if (!REVERT && !TARGET_UID) {
  console.error(
    'Usage: node claim-stations.js <uid> [--dry-run] [--from=<currentPartnerId>]\n' +
    '       node claim-stations.js --revert [--from=<currentPartnerId>]\n\n' +
    'Find the uid in Firebase Console → Authentication → Users.'
  );
  process.exit(1);
}

// Sanity-check the uid shape so a typo doesn't silently rewrite docs
// to garbage. Firebase uids are 28 chars, [A-Za-z0-9]. We tolerate
// shorter test uids but reject anything that looks like a flag value.
if (TARGET_UID && (TARGET_UID.includes('=') || TARGET_UID.startsWith('-'))) {
  console.error(`uid "${TARGET_UID}" looks malformed — did you forget a positional arg?`);
  process.exit(1);
}

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

async function main() {
  const serviceAccount = await loadServiceAccount();
  const projectId = serviceAccount.project_id;
  initializeApp({ credential: cert(serviceAccount), projectId });
  const db = getFirestore();

  const newOwner = REVERT ? 'system-seed' : TARGET_UID;
  const verb = REVERT ? 'reverting' : 'claiming';

  console.log(`Connected to project "${projectId}".`);
  console.log(`${verb} stations where partnerId == "${FROM}" → "${newOwner}"…`);

  const snap = await db
    .collection('stations')
    .where('partnerId', '==', FROM)
    .get();

  if (snap.empty) {
    console.log(`  (no stations matched partnerId == "${FROM}")`);
    return;
  }

  if (DRY_RUN) {
    console.log(`[dry-run] would update ${snap.size} doc(s):`);
    snap.docs.forEach((d) => {
      const data = d.data();
      console.log(`  - ${d.id.padEnd(14)} ${data.name ?? '(no name)'}`);
    });
    return;
  }

  const batch = db.batch();
  snap.docs.forEach((d) => {
    batch.update(d.ref, {
      partnerId: newOwner,
      claimedAt: FieldValue.serverTimestamp(),
    });
  });
  await batch.commit();

  snap.docs.forEach((d) => {
    const data = d.data();
    console.log(`  ✓ ${d.id.padEnd(14)} ${data.name ?? '(no name)'}`);
  });
  console.log(`Done — ${snap.size} doc(s) updated.`);
}

main().catch((err) => {
  console.error('Claim failed:', err);
  process.exit(1);
});
