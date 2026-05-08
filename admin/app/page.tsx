'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAdminAuth } from '@/lib/auth';

/// Root entry point — funnels every visit through the admin gate
/// before letting them past. The auth hook resolves quickly off the
/// cached Firebase session, so the loading flash is usually <100ms.
export default function HomePage() {
  const router = useRouter();
  const auth = useAdminAuth();

  useEffect(() => {
    if (auth.status === 'admin') router.replace('/overview');
    if (auth.status === 'signed-out') router.replace('/sign-in');
    if (auth.status === 'not-admin') router.replace('/sign-in?denied=1');
  }, [auth.status, router]);

  return (
    <div className="flex min-h-screen items-center justify-center text-fg-3">
      <span className="text-sm">Loading…</span>
    </div>
  );
}
