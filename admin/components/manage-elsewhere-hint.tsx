'use client';

import Link from 'next/link';
import { Info } from 'lucide-react';

/**
 * Inline reminder shown above read-only screens that points the
 * admin at the Capabilities page when they need to mutate data.
 * Keeps the per-screen surface light without losing discoverability.
 */
export function ManageElsewhereHint({ topic }: { topic: string }) {
  return (
    <div className="mb-4 flex items-start gap-2.5 rounded-md border border-rule bg-surface-2/50 px-3 py-2 text-[12px] text-fg-3">
      <Info size={13} className="mt-0.5 shrink-0" />
      <span>
        Need to {topic}? See{' '}
        <Link
          href="/capabilities"
          className="font-medium text-accent hover:underline"
        >
          Capabilities
        </Link>{' '}
        for the workaround until it lands in this view.
      </span>
    </div>
  );
}
