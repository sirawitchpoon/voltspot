'use client';

/**
 * Admin gate. Mirrors the iOS RootView routing pattern (App/AppSession
 * + RootView switch on (user, role)) — the dashboard renders only
 * when the signed-in user carries the `role: "admin"` Firebase
 * custom claim. Granted via `scripts/grant-admin.js`.
 *
 * The hook returns one of three states so calling components can
 * branch cleanly: pending (don't render anything yet), unauthorised
 * (redirect to /sign-in), authorised (render the page).
 */
import { onAuthStateChanged, type User } from 'firebase/auth';
import { useEffect, useState } from 'react';
import { firebaseAuth } from './firebase';

export type AdminAuthState =
  | { status: 'pending' }
  | { status: 'signed-out' }
  | { status: 'not-admin'; user: User }
  | { status: 'admin'; user: User };

export function useAdminAuth(): AdminAuthState {
  const [state, setState] = useState<AdminAuthState>({ status: 'pending' });

  useEffect(() => {
    const auth = firebaseAuth();
    const unsub = onAuthStateChanged(auth, async (user) => {
      if (!user) {
        setState({ status: 'signed-out' });
        return;
      }
      // forceRefresh=true so we pick up a freshly granted claim
      // without waiting for the cached token to expire.
      const token = await user.getIdTokenResult(true);
      if (token.claims.role === 'admin') {
        setState({ status: 'admin', user });
      } else {
        setState({ status: 'not-admin', user });
      }
    });
    return unsub;
  }, []);

  return state;
}
