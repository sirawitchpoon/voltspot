#!/usr/bin/env node
/**
 * Grants the `role: "admin"` Firebase custom claim to a uid so the
 * admin webapp (admin/) lets them past the auth gate and Firestore
 * rules grant network-wide read access.
 *
 * Mirrors the claim-stations.js conventions: uid as positional arg,
 * --dry-run + --revoke flags, --list to enumerate current admins.
 *
 * Usage:
 *   cd scripts && node grant-admin.js <uid>           # grant
 *   cd scripts && node grant-admin.js <uid> --revoke  # demote
 *   cd scripts && node grant-admin.js --list          # who has it
 *
 * After granting, the user must sign out and back in (or call
 * `getIdToken(true)` in the webapp) to pick up the new claim — Firebase
 * caches ID tokens for up to an hour by default. The webapp's
 * useAdminAuth hook calls getIdTokenResult(true) so the next page
 * load reflects the change.
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SERVICE_ACCOUNT_PATH = resolve(__dirname, 'service-account.json');

const argv = process.argv.slice(2);
const flags = new Set(argv.filter((a) => a.startsWith('--')));
const positional = argv.filter((a) => !a.startsWith('-'));

const DRY_RUN = flags.has('--dry-run');
const REVOKE = flags.has('--revoke');
const LIST = flags.has('--list');

const TARGET_UID = positional[0];

if (!LIST && !TARGET_UID) {
  console.error(
    'Usage:\n' +
    '  node grant-admin.js <uid> [--dry-run]     grant admin role\n' +
    '  node grant-admin.js <uid> --revoke        demote\n' +
    '  node grant-admin.js --list                list current admins\n'
  );
  process.exit(1);
}

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
  const auth = getAuth();
  console.log(`Connected to project "${serviceAccount.project_id}".`);

  if (LIST) {
    console.log('Listing accounts with role == "admin"…');
    let pageToken;
    let count = 0;
    do {
      const page = await auth.listUsers(1000, pageToken);
      for (const u of page.users) {
        if (u.customClaims?.role === 'admin') {
          console.log(`  ${u.uid}  ${u.email ?? '(no email)'}`);
          count++;
        }
      }
      pageToken = page.pageToken;
    } while (pageToken);
    console.log(`Total: ${count} admin(s).`);
    return;
  }

  // Read existing claims first so a revoke or re-grant doesn't blow
  // away unrelated claims another script may have set.
  const user = await auth.getUser(TARGET_UID);
  const existing = user.customClaims ?? {};
  const next = { ...existing };
  if (REVOKE) {
    delete next.role;
  } else {
    next.role = 'admin';
  }

  if (DRY_RUN) {
    console.log(`[dry-run] uid=${TARGET_UID} (${user.email ?? 'no email'})`);
    console.log(`  before: ${JSON.stringify(existing)}`);
    console.log(`  after:  ${JSON.stringify(next)}`);
    return;
  }

  await auth.setCustomUserClaims(TARGET_UID, next);
  console.log(`✓ uid=${TARGET_UID} (${user.email ?? 'no email'})`);
  console.log(`  role: ${next.role ?? '(none)'}`);
  console.log('  Sign out + back in to pick up the new token.');
}

main().catch((err) => {
  console.error('Failed:', err);
  process.exit(1);
});
