'use client';

/**
 * Capabilities — the master "what can I do here, and where" page.
 * Mirrors the Asana board so the founder can answer the question
 * "do I need to leave the webapp to do X?" without context-switching.
 *
 * Surfaces:
 *   - Routes for live capabilities (clickable).
 *   - CLI commands + Firebase Console deep-links for workarounds.
 *   - The blocking dependency for Phase 2/3 items.
 */
import Link from 'next/link';
import { ArrowUpRight, ChevronRight, Terminal } from 'lucide-react';
import { DashShell } from '@/components/dash-shell';
import {
  CAPABILITIES,
  STATUS_LABEL,
  STATUS_DESCRIPTION,
  type Capability,
  type CapabilityStatus,
} from '@/lib/capabilities';
import { cn } from '@/lib/utils';

const ORDER: CapabilityStatus[] = ['live', 'workaround', 'phase2', 'phase3'];

export default function CapabilitiesPage() {
  const grouped: Record<CapabilityStatus, Capability[]> = {
    live: [],
    workaround: [],
    phase2: [],
    phase3: [],
  };
  for (const c of CAPABILITIES) grouped[c.status].push(c);

  return (
    <DashShell>
      <header className="mb-6">
        <h2 className="text-2xl font-bold">Capabilities</h2>
        <p className="mt-1 text-sm text-fg-3">
          What you can do in this webapp today, and where to go for everything else.
        </p>
      </header>

      <div className="space-y-6">
        {ORDER.map((status) => {
          const entries = grouped[status];
          if (entries.length === 0) return null;
          return (
            <section key={status} className="rounded-lg border border-rule bg-surface">
              <header className="flex items-center justify-between border-b border-rule px-4 py-3">
                <div className="flex items-center gap-3">
                  <StatusPill status={status} />
                  <span className="text-sm text-fg-3">{STATUS_DESCRIPTION[status]}</span>
                </div>
                <span className="text-[11px] text-fg-3 tabular">
                  {entries.length} item{entries.length === 1 ? '' : 's'}
                </span>
              </header>
              <ul className="divide-y divide-rule">
                {entries.map((cap) => (
                  <CapabilityRow key={cap.id} capability={cap} />
                ))}
              </ul>
            </section>
          );
        })}
      </div>
    </DashShell>
  );
}

function CapabilityRow({ capability }: { capability: Capability }) {
  return (
    <li className="px-4 py-3">
      <div className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h3 className="text-sm font-semibold text-fg">{capability.title}</h3>
          <p className="mt-0.5 text-[12px] text-fg-3">{capability.summary}</p>

          {capability.status === 'live' && capability.route && (
            <Link
              href={capability.route}
              className="mt-2 inline-flex items-center gap-1 text-[12px] font-medium text-accent hover:underline"
            >
              Open {capability.route}
              <ChevronRight size={12} />
            </Link>
          )}

          {capability.workaround && (
            <pre className="mt-2 max-w-full overflow-x-auto rounded-md border border-rule bg-surface-2 p-2.5 text-[11px] leading-relaxed text-fg-2">
              <Terminal size={11} className="mr-1.5 inline-block text-fg-3" />
              <span className="whitespace-pre-wrap font-mono">{capability.workaround}</span>
            </pre>
          )}

          {capability.externalUrl && (
            <a
              href={capability.externalUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-2 inline-flex items-center gap-1 text-[12px] font-medium text-accent hover:underline"
            >
              {capability.externalLabel ?? 'Open external console'}
              <ArrowUpRight size={12} />
            </a>
          )}

          {capability.blockedBy && (
            <p className="mt-2 text-[11px] text-fg-3">
              <span className="font-semibold text-fg-2">Blocked by: </span>
              {capability.blockedBy}
            </p>
          )}
        </div>
      </div>
    </li>
  );
}

function StatusPill({ status }: { status: CapabilityStatus }) {
  return (
    <span
      className={cn(
        'rounded-full px-2.5 py-1 text-[11px] font-semibold uppercase tracking-wide',
        statusPillClass(status),
      )}
    >
      {STATUS_LABEL[status]}
    </span>
  );
}

function statusPillClass(status: CapabilityStatus): string {
  switch (status) {
    case 'live':
      return 'bg-success/15 text-success';
    case 'workaround':
      return 'bg-warning/15 text-warning';
    case 'phase2':
      return 'bg-accent/20 text-accent';
    case 'phase3':
      return 'bg-fg-3/15 text-fg-3';
  }
}
