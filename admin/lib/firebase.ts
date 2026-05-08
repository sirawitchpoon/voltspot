'use client';

/**
 * Firebase Web SDK initialiser. We attach to the same project as the
 * iOS app (voltspot-e410c) so reads see the exact same docs the
 * Partner-side iOS screens already use.
 *
 * Initialisation runs once per browser tab thanks to `getApps()`
 * dedupe — Next.js can re-execute this module under fast-refresh and
 * we'd otherwise get the "Firebase App named '[DEFAULT]' already
 * exists" error.
 */
import { initializeApp, getApps, type FirebaseApp } from 'firebase/app';
import { getAuth, type Auth } from 'firebase/auth';
import { getFirestore, type Firestore } from 'firebase/firestore';

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

let cachedApp: FirebaseApp | null = null;

/// Lazy because this file gets imported at build time during the
/// static export — env vars are evaluated then, not at runtime, so
/// the build still succeeds when keys are missing in CI. The first
/// real call happens in the browser where keys are populated.
function getApp(): FirebaseApp {
  if (cachedApp) return cachedApp;
  cachedApp = getApps()[0] ?? initializeApp(firebaseConfig);
  return cachedApp;
}

export function firebaseAuth(): Auth {
  return getAuth(getApp());
}

export function firestore(): Firestore {
  return getFirestore(getApp());
}
