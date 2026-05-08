# Voltspot Admin Console

Internal operations dashboard. Reads Firestore directly via the
Firebase Web SDK and ships as a static export — no Cloud Functions or
Cloud Run involved, so hosting stays on Firebase Hosting's free tier
during the pre-funding window.

## First-run setup (one-time, ~10 minutes)

### 1. Add a Web app in Firebase Console
- Console → Project settings → "Your apps" → **Add app** → Web
- App nickname: `voltspot-admin` (any value works)
- Skip Firebase Hosting setup here — we'll wire that ourselves
- Copy the SDK config block

### 2. Fill `.env.local`
```bash
cd admin
cp .env.local.example .env.local
# then paste apiKey, authDomain, etc. from the Firebase config
```

### 3. Grant your account the admin role
```bash
cd ../scripts
node grant-admin.js <your-uid>
# verify: node grant-admin.js --list
```
Sign out / back in (or just refresh) so the new ID token includes the
`role: "admin"` custom claim.

### 4. Deploy the updated Firestore rules
```bash
cd ../deploy
firebase deploy --only firestore:rules,firestore:indexes
```
This activates the `isAdmin()` helper added to `firestore.rules` so
the admin reads stop hitting `permission-denied`.

## Run locally

```bash
cd admin
npm install      # first time only
npm run dev      # http://localhost:3000
```

## Deploy to Firebase Hosting

```bash
cd admin
npm run build    # produces ./out/
cd ../deploy
firebase deploy --only hosting
# → https://<project-id>.web.app
```

`deploy/firebase.json` runs `npm run build` automatically as a
predeploy hook, so `firebase deploy --only hosting` from `deploy/` is
the one-liner once `.env.local` is in place.

## Architecture notes

- **No backend service**. Every read is a Firestore query from the
  browser. The admin gate is a Firebase custom claim (`role: "admin"`)
  enforced both client-side (auth hook) and server-side (Firestore
  rules `isAdmin()` helper).
- **Static export**. `next.config.ts` sets `output: 'export'` —
  every page must be client-renderable, no server runtime allowed.
  Dynamic routes are out; we use slide-over panels for detail views
  instead.
- **Realtime via `onSnapshot`**. Map markers and the Sessions feed
  subscribe directly to Firestore so demo flips show up within ~1
  second.
- **Tokens live in lockstep with iOS**. `lib/types.ts` mirrors
  `Voltspot/Domain/Entities/*.swift` field-for-field; the satang
  invariant matches `Core/Localization/CurrencyFormatter.swift`.

## Routes

| Path | Purpose |
| --- | --- |
| `/` | Auth router — funnels to `/sign-in` or `/overview` |
| `/sign-in` | Email + password gate; rejects non-admin tokens |
| `/overview` | KPI cards + 30-day revenue chart |
| `/map` | Interactive map with live status colors |
| `/stations` | Sortable table + slide-over detail panel |
| `/sessions` | Realtime feed + filters + expandable rows |
