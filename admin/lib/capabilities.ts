/**
 * Single source of truth for "what can the admin do, and where."
 *
 * Mirrors the Asana board "Voltspot Admin Console — Capability Board"
 * but lives in the webapp itself so a signed-in admin can see the
 * same matrix without context-switching. When you ship a capability
 * (move it from `workaround` -> `live`), update both this file AND
 * the matching Asana task in one PR — a slightly redundant rule, but
 * it keeps the two in lockstep without coupling the build to Asana's
 * API.
 */

export type CapabilityStatus = 'live' | 'workaround' | 'phase2' | 'phase3';

export interface Capability {
  id: string;
  title: string;
  /** One-line summary surfaced in the table view. */
  summary: string;
  status: CapabilityStatus;
  /** Where the admin webapp surfaces it (route) — only for `live`. */
  route?: string;
  /**
   * Step-by-step or shell command for the workaround. Pre-formatted
   * with backticks where appropriate; the renderer treats it as plain
   * text.
   */
  workaround?: string;
  /** External console URL when the action lives in someone else's tool. */
  externalUrl?: string;
  externalLabel?: string;
  /** What's blocking the move into the webapp (Phase 2 / Phase 3 only). */
  blockedBy?: string;
}

export const CAPABILITIES: Capability[] = [
  // ----- Live ------------------------------------------------------------
  {
    id: 'overview',
    title: 'View network overview (KPIs + revenue trend)',
    summary: '4 KPI cards + 30-day daily revenue chart, live via Firestore listeners.',
    status: 'live',
    route: '/overview',
  },
  {
    id: 'map',
    title: 'Map with live status colors',
    summary: 'Markers re-color in real time as connector_status changes.',
    status: 'live',
    route: '/map',
  },
  {
    id: 'stations-list',
    title: 'Browse stations table + detail',
    summary: 'Sortable columns + slide-over panel showing connectors, tariff, recent sessions.',
    status: 'live',
    route: '/stations',
  },
  {
    id: 'sessions-feed',
    title: 'Sessions feed (live + filterable)',
    summary: 'Latest 100 sessions, filterable by status and station, expandable rows.',
    status: 'live',
    route: '/sessions',
  },
  {
    id: 'sign-in',
    title: 'Email + password sign-in (admin gate)',
    summary: 'Firebase Auth with role: admin custom claim enforced both client- and server-side.',
    status: 'live',
    route: '/sign-in',
  },

  // ----- Workarounds -----------------------------------------------------
  {
    id: 'station-crud',
    title: 'Add / edit / delete stations',
    summary: 'Geohash recomputation matters — manual Console edits skip it.',
    status: 'workaround',
    workaround: 'Firebase Console → Firestore → /stations/{id} (manual)\nOr: cd scripts && node seed-stations.js (full reseed)',
    externalUrl: 'https://console.firebase.google.com/project/voltspot-e410c/firestore/data/~2Fstations',
    externalLabel: 'Open Firestore: /stations',
  },
  {
    id: 'tariff-edit',
    title: 'Edit a station tariff',
    summary: 'Price per kWh + session fee — once partners onboard this needs an audit trail.',
    status: 'workaround',
    workaround: 'Firebase Console → /stations/{id}.tariff → edit pricePerKWhSatang (integer satang) and sessionFeeSatang.',
    externalUrl: 'https://console.firebase.google.com/project/voltspot-e410c/firestore/data/~2Fstations',
    externalLabel: 'Open Firestore: /stations',
  },
  {
    id: 'claim-stations',
    title: 'Assign / re-assign stations to a partner',
    summary: 'Bulk-update the partnerId field on every seed station.',
    status: 'workaround',
    workaround: 'cd scripts && node claim-stations.js <partner-uid>\nOptional: --from=<currentPartnerId> to transfer between partners',
  },
  {
    id: 'rename-stations',
    title: 'Add Thai station names / addresses',
    summary: 'Updates only name + address fields; preserves partnerId.',
    status: 'workaround',
    workaround: 'cd scripts && node rename-stations.js [--dry-run]',
  },
  {
    id: 'seed-sessions',
    title: 'Seed demo sessions (pitch / load testing)',
    summary: '~150 synthetic sessions across 30 days. Demo-only userId.',
    status: 'workaround',
    workaround: 'cd scripts && node seed-sessions.js <partner-uid> [--reset]',
  },
  {
    id: 'grant-admin',
    title: 'Grant / revoke admin role',
    summary: 'Firebase custom claims; sign out + back in to refresh the token.',
    status: 'workaround',
    workaround: 'cd scripts && node grant-admin.js <uid>\nList: --list   Revoke: --revoke',
  },
  {
    id: 'user-mgmt',
    title: 'Reset / disable a user account',
    summary: 'Lock out a compromised account or hard-delete a tester.',
    status: 'workaround',
    workaround: 'Firebase Console → Authentication → Users → ⋯ → Disable / Delete',
    externalUrl: 'https://console.firebase.google.com/project/voltspot-e410c/authentication/users',
    externalLabel: 'Open Firebase Auth → Users',
  },
  {
    id: 'rules-deploy',
    title: 'Edit Firestore rules + indexes',
    summary: 'Stays in code on purpose — diffs go through PR review, not a GUI.',
    status: 'workaround',
    workaround: 'Edit deploy/firestore.rules + firestore.indexes.json\nDeploy: cd deploy && firebase deploy --only firestore:rules,firestore:indexes',
  },
  {
    id: 'code-deploy',
    title: 'Deploy code (iOS, admin webapp, Gateway)',
    summary: 'iOS via Xcode; admin via Firebase Hosting; Gateway via Cloud Build (Phase 2).',
    status: 'workaround',
    workaround: 'iOS: Xcode → Cmd+R or Archive\nAdmin: cd admin && npm run build && cd ../deploy && firebase deploy --only hosting\nGateway: cd backend/ocpp-gateway && gcloud builds submit (Phase 2)',
  },
  {
    id: 'billing',
    title: 'View Firebase / GCP billing',
    summary: 'Track Spark / Blaze usage, Cloud Run cost when deployed.',
    status: 'workaround',
    workaround: 'Firebase Console → Usage and billing | GCP Console → Billing',
    externalUrl: 'https://console.firebase.google.com/project/voltspot-e410c/usage',
    externalLabel: 'Open Firebase → Usage & Billing',
  },

  // ----- Phase 2 (post-funding, after Cloud Run is live) -----------------
  {
    id: 'force-stop',
    title: 'Force-stop an active session (admin override)',
    summary: 'OCPP RemoteStopTransaction issued from the Stop button on a session row.',
    status: 'phase2',
    blockedBy: 'Cloud Run deploy + new /api/admin/sessions/{txId}/force-stop endpoint with requireAdmin middleware.',
  },
  {
    id: 'reset-charger',
    title: 'Remote-restart a faulted charger',
    summary: 'OCPP Reset (Soft|Hard) — clears ~90% of connector faults.',
    status: 'phase2',
    blockedBy: 'Cloud Run deploy + /api/admin/chargers/{id}/reset endpoint.',
  },
  {
    id: 'refund',
    title: 'Refund a completed session',
    summary: 'Triggers payment provider refund + flips status to "refunded".',
    status: 'phase2',
    blockedBy: 'Payment provider integration (Stripe / 2C2P) — itself a Phase 2 dependency.',
  },
  {
    id: 'suspend-partner',
    title: 'Suspend a partner',
    summary: 'Writes partners/{uid}.suspended = true; rules block new sessions.',
    status: 'phase2',
    blockedBy: 'Phase 2 mutation API + audit log entry.',
  },
  {
    id: 'gateway-health',
    title: 'Gateway health (uptime, latency, error rate)',
    summary: 'p50/p95 OCPP call latency, in-flight WS count, error budget.',
    status: 'phase2',
    blockedBy: 'Cloud Run deploy + Cloud Logging → BigQuery sink.',
  },
  {
    id: 'audit-log',
    title: 'Audit log for every admin action',
    summary: 'New /audit_log collection; every mutating endpoint logs adminUid, action, diff, ts.',
    status: 'phase2',
    blockedBy: 'Phase 2 mutation API (no point logging reads).',
  },

  // ----- Phase 3 (long-term) ---------------------------------------------
  {
    id: 'partners-directory',
    title: 'Partner directory + per-partner drilldown',
    summary: 'Per-partner /overview clone scoped to their stations.',
    status: 'phase3',
  },
  {
    id: 'bigquery',
    title: 'BigQuery analytics export (>30 days)',
    summary: 'Stream sessions to BQ; analytics tab in webapp driven by BQ queries.',
    status: 'phase3',
  },
  {
    id: 'fcm-campaigns',
    title: 'Push notification campaigns',
    summary: 'Compose + send FCM messages to a segment with moderation gate.',
    status: 'phase3',
  },
  {
    id: 'rbac-roles',
    title: 'Multi-role RBAC (admin / support / finance)',
    summary: 'Split today\'s monolithic admin claim into purpose-built roles.',
    status: 'phase3',
  },
  {
    id: 'custom-domain',
    title: 'Custom domain (admin.voltspot.app)',
    summary: 'Cloudflare Registrar at-cost + Firebase Hosting custom domain.',
    status: 'phase3',
  },
  {
    id: 'i18n',
    title: 'Webapp i18n (Thai / English toggle)',
    summary: 'Mirror the iOS Localizable.xcstrings approach via next-intl.',
    status: 'phase3',
  },
  {
    id: 'csv-export',
    title: 'Export sessions CSV + scheduled email reports',
    summary: 'Self-serve reporting + daily summary email to ops@.',
    status: 'phase3',
  },
];

export const STATUS_LABEL: Record<CapabilityStatus, string> = {
  live: 'Live',
  workaround: 'Workaround',
  phase2: 'Phase 2',
  phase3: 'Phase 3',
};

export const STATUS_DESCRIPTION: Record<CapabilityStatus, string> = {
  live: 'Available in the webapp today.',
  workaround: 'Possible, but you must drop into Firebase Console / GCP / a CLI script.',
  phase2: 'Planned. Unlocks after the OCPP Gateway ships on Cloud Run.',
  phase3: 'On the long-term roadmap; revisit after the May 23 pitch.',
};
