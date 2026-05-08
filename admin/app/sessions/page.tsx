'use client';

/**
 * Sessions feed — chronological log of every charging session that
 * ever fired across the network. Live via `subscribeRecentSessions`
 * so a new session created mid-demo pops in at the top without a
 * refresh — that's the realtime story for investors.
 *
 * Filters today are intentionally narrow (status + station) — wider
 * filtering (date range, partner) will need extra composite indexes
 * which we'll add piecewise as the screens demand them.
 */
import { useEffect, useMemo, useState } from 'react';
import { ChevronDown, ChevronUp, Filter } from 'lucide-react';
import { DashShell } from '@/components/dash-shell';
import { ManageElsewhereHint } from '@/components/manage-elsewhere-hint';
import {
  fetchAllStations,
  subscribeRecentSessions,
} from '@/lib/queries';
import type { ChargingSession, SessionStatus, Station } from '@/lib/types';
import { kWh, satangToBaht } from '@/lib/satang';
import { cn } from '@/lib/utils';

const PAGE_SIZE = 100;

const STATUS_OPTIONS: SessionStatus[] = ['active', 'completed', 'failed', 'interrupted'];

export default function SessionsPage() {
  const [sessions, setSessions] = useState<ChargingSession[] | null>(null);
  const [stations, setStations] = useState<Station[]>([]);
  const [statusFilter, setStatusFilter] = useState<SessionStatus | 'all'>('all');
  const [stationFilter, setStationFilter] = useState<string | 'all'>('all');
  const [expanded, setExpanded] = useState<string | null>(null);

  useEffect(() => {
    const unsub = subscribeRecentSessions(PAGE_SIZE, setSessions);
    fetchAllStations().then(setStations).catch(() => setStations([]));
    return unsub;
  }, []);

  const stationLookup = useMemo(() => {
    const map = new Map<string, Station>();
    for (const s of stations) map.set(s.id, s);
    return map;
  }, [stations]);

  const filtered = useMemo(() => {
    if (!sessions) return null;
    return sessions.filter((s) => {
      if (statusFilter !== 'all' && s.status !== statusFilter) return false;
      if (stationFilter !== 'all' && s.stationId !== stationFilter) return false;
      return true;
    });
  }, [sessions, statusFilter, stationFilter]);

  return (
    <DashShell>
      <header className="mb-4 flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-2xl font-bold">Sessions</h2>
          <p className="mt-1 text-sm text-fg-3">
            {sessions == null
              ? 'Loading…'
              : `Most recent ${sessions.length} sessions · live updates`}
          </p>
        </div>

        <div className="flex items-center gap-2 text-xs">
          <Filter size={13} className="text-fg-3" />
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value as SessionStatus | 'all')}
            className="rounded-md border border-rule bg-surface px-2 py-1.5"
          >
            <option value="all">All statuses</option>
            {STATUS_OPTIONS.map((s) => (
              <option key={s} value={s}>
                {s}
              </option>
            ))}
          </select>
          <select
            value={stationFilter}
            onChange={(e) => setStationFilter(e.target.value)}
            className="rounded-md border border-rule bg-surface px-2 py-1.5"
          >
            <option value="all">All stations</option>
            {stations.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        </div>
      </header>

      <ManageElsewhereHint topic="force-stop or refund a session" />

      <div className="overflow-hidden rounded-lg border border-rule bg-surface">
        <div className="hidden grid-cols-[80px_1.4fr_1fr_0.8fr_0.8fr_0.8fr_28px] items-center gap-3 border-b border-rule px-4 py-2 text-[11px] font-semibold uppercase tracking-wide text-fg-3 md:grid">
          <span>Status</span>
          <span>Station</span>
          <span>Started</span>
          <span>Energy</span>
          <span>Cost</span>
          <span>User</span>
          <span />
        </div>

        {filtered == null ? (
          Array.from({ length: 8 }).map((_, i) => (
            <div key={i} className="h-12 animate-pulse border-b border-rule bg-surface-2/50" />
          ))
        ) : filtered.length === 0 ? (
          <div className="px-4 py-8 text-center text-sm text-fg-3">
            No sessions match these filters.
          </div>
        ) : (
          filtered.map((session) => {
            const station = stationLookup.get(session.stationId);
            const isOpen = expanded === session.id;
            return (
              <div key={session.id} className="border-b border-rule last:border-b-0">
                <button
                  type="button"
                  onClick={() => setExpanded(isOpen ? null : session.id)}
                  className="grid w-full grid-cols-[80px_1.4fr_1fr_0.8fr_0.8fr_0.8fr_28px] items-center gap-3 px-4 py-3 text-left text-sm transition hover:bg-surface-2"
                >
                  <span
                    className={cn(
                      'inline-block w-fit rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide',
                      sessionBadgeClass(session.status),
                    )}
                  >
                    {session.status}
                  </span>
                  <div className="min-w-0">
                    <div className="truncate font-medium text-fg">
                      {station?.name ?? session.stationId}
                    </div>
                    <div className="truncate text-[11px] text-fg-3 tabular">
                      connector {session.connectorId}
                    </div>
                  </div>
                  <span className="text-fg-2 tabular">
                    {session.startedAt.toLocaleString()}
                  </span>
                  <span className="text-fg-2 tabular">{kWh(session.energyKWh)}</span>
                  <span className="font-semibold text-fg tabular">
                    {satangToBaht(session.costSatang)}
                  </span>
                  <span className="truncate text-[11px] text-fg-3 tabular">
                    {session.userId ?? '—'}
                  </span>
                  {isOpen ? (
                    <ChevronUp size={14} className="text-fg-3" />
                  ) : (
                    <ChevronDown size={14} className="text-fg-3" />
                  )}
                </button>

                {isOpen && (
                  <div className="grid grid-cols-2 gap-3 bg-surface-2/60 px-4 py-3 text-[11px] md:grid-cols-4">
                    <Detail label="Session ID" value={session.id} />
                    <Detail
                      label="Duration"
                      value={
                        session.endedAt
                          ? formatDuration(session.endedAt.getTime() - session.startedAt.getTime())
                          : 'in progress'
                      }
                    />
                    <Detail
                      label="Effective rate"
                      value={
                        session.energyKWh > 0
                          ? satangToBaht(Math.round(session.costSatang / session.energyKWh)) + ' / kWh'
                          : '—'
                      }
                    />
                    <Detail label="Partner" value={session.partnerId ?? '—'} mono />
                  </div>
                )}
              </div>
            );
          })
        )}
      </div>
    </DashShell>
  );
}

function Detail({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div>
      <div className="text-[10px] uppercase tracking-wide text-fg-3">{label}</div>
      <div className={cn('mt-0.5 text-fg', mono && 'font-mono text-[11px]')}>{value}</div>
    </div>
  );
}

function sessionBadgeClass(status: string): string {
  switch (status) {
    case 'active':
      return 'bg-accent/20 text-accent';
    case 'completed':
      return 'bg-success/15 text-success';
    case 'failed':
    case 'interrupted':
      return 'bg-danger/15 text-danger';
    default:
      return 'bg-fg-3/15 text-fg-3';
  }
}

function formatDuration(ms: number): string {
  const totalSec = Math.max(0, Math.round(ms / 1000));
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}
