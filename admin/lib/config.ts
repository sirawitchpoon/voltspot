/**
 * Single source for app-level branding. Mirrors the iOS
 * AppConfig.appName invariant — the literal brand string must NOT
 * appear anywhere else under admin/. CI verification:
 *
 *   grep -rn '"Voltspot"' admin/ --include='*.tsx' --include='*.ts'
 *   # expect: zero matches outside this file
 */
export const APP_NAME = process.env.NEXT_PUBLIC_APP_NAME ?? 'Voltspot';

export const FIREBASE_PROJECT_ID =
  process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID ?? '';
