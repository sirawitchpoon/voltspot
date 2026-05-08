'use client';

/**
 * Email + password sign-in. We deliberately don't expose social
 * providers (Apple/Google) here — admins are provisioned manually
 * via `scripts/grant-admin.js` and email/password is the most
 * predictable surface for a small ops set. Adding Google later is
 * trivial if the team grows.
 */
import { useState, useEffect, Suspense } from 'react';
import { signInWithEmailAndPassword } from 'firebase/auth';
import { useRouter, useSearchParams } from 'next/navigation';
import { firebaseAuth } from '@/lib/firebase';
import { useAdminAuth } from '@/lib/auth';
import { APP_NAME } from '@/lib/config';

function SignInForm() {
  const router = useRouter();
  const params = useSearchParams();
  const auth = useAdminAuth();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const denied = params.get('denied') === '1';

  // Once Firebase confirms the session is admin, bounce to /overview
  // — this lets us land on /sign-in directly and still get redirected
  // when we already have a valid token.
  useEffect(() => {
    if (auth.status === 'admin') router.replace('/overview');
  }, [auth.status, router]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      await signInWithEmailAndPassword(firebaseAuth(), email, password);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center px-4">
      <form
        onSubmit={handleSubmit}
        className="w-full max-w-sm rounded-lg border border-rule bg-surface p-6 shadow-sm"
      >
        <h1 className="mb-1 text-lg font-semibold">{APP_NAME} · Admin</h1>
        <p className="mb-6 text-sm text-fg-3">
          Sign in to the operations console.
        </p>

        {denied && (
          <div className="mb-4 rounded-md border border-danger/40 bg-danger/5 px-3 py-2 text-xs text-danger">
            Your account does not have admin access. Ask the founder to grant
            the admin role.
          </div>
        )}

        <label className="mb-3 block">
          <span className="mb-1 block text-xs font-medium text-fg-2">Email</span>
          <input
            type="email"
            autoComplete="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full rounded-md border border-rule bg-surface-2 px-3 py-2 text-sm focus:border-accent focus:outline-none"
          />
        </label>
        <label className="mb-5 block">
          <span className="mb-1 block text-xs font-medium text-fg-2">Password</span>
          <input
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full rounded-md border border-rule bg-surface-2 px-3 py-2 text-sm focus:border-accent focus:outline-none"
          />
        </label>

        {error && (
          <div className="mb-4 text-xs text-danger" role="alert">
            {error}
          </div>
        )}

        <button
          type="submit"
          disabled={submitting}
          className="w-full rounded-md bg-accent px-4 py-2 text-sm font-semibold text-white transition hover:opacity-90 disabled:opacity-50"
        >
          {submitting ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </main>
  );
}

export default function SignInPage() {
  return (
    <Suspense fallback={<main className="flex min-h-screen items-center justify-center text-fg-3">Loading…</main>}>
      <SignInForm />
    </Suspense>
  );
}
