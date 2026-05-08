'use client';

/**
 * Stations table — every station the partner has registered, with
 * sortable columns and a slide-over detail panel. The detail lives
 * in a panel rather than a dedicated `/stations/[id]` page because
 * Next.js static export requires `generateStaticParams` for dynamic
 * routes — and Firestore IDs aren't known at build time. Side panels
 * are also faster to scan during ops triage (Linear, Stripe pattern).
 */
import { useEffect, useMemo, useState } from 'react';
import { ArrowDown, ArrowUp, Plug, ChevronRight, X } from 'lucide-react';
import { DashShell } from '@/components/dash-shell';
import { ManageElsewhereHint } from '@/components/manage-elsewhere-hint';
import {
  fetchAllStations,
  fetchSessions,
  subscribeConnectorStatuses,
} from '@/lib/queries';
import type {
  ChargingSession,
  ConnectorLiveStatus,
  Station,
} from '@/lib/types';
import { kWh, satangToBaht } from '@/lib/satang';
import { cn } from '@/lib/utils';

type SortKey = 'name' | 'connectors' | 'price' | 'live';
type SortDir = 'asc' | 'desc';

export default function StationsPage() {
  const [stations, setStations] = useState<Station[] | null>(null);
  const [statuses, setStatuses] = useState<ConnectorLiveStatus[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [sortKey, setSortKey] = useState<SortKey>('name');
  const [sortDir, setSortDir] = useState<SortDir>('asc');
  const [selectedId, setSelectedId] = useState<string | null>(null);

  useEffect(() => {
    fetchAllStations()
      .then(setStations)
      .catch((e: Error) => setError(e.message));
    const unsub = subscribeConnectorStatuses(setStatuses);
    return unsub;
  }, []);

  const liveByStation = useMemo(() => {
    const map = new Map<string, number>();
    for (const s of statuses) {
      if (s.status === 'Charging' || s.status === 'Available') {
        map.set(s.stationId, (map.get(s.stationId) ?? 0) + 1);
      }
    }
    return map;
  }, [statuses]);

  const sorted = useMemo(() => {
    if (!stations) return null;
    const dir = sortDir === 'asc' ? 1 : -1;
    return [...stations].sort((a, b) => {
      switch (sortKey) {
        case 'name':
          return a.name.localeCompare(b.name) * dir;
        case 'connectors':
          return (a.connectors.length - b.connectors.length) * dir;
        case 'price':
          return (a.tariff.pricePerKWhSatang - b.tariff.pricePerKWhSatang) * dir;
        case 'live':
          return ((liveByStation.get(a.id) ?? 0) - (liveByStation.get(b.id) ?? 0)) * dir;
      }
    });
  }, [stations, sortKey, sortDir, liveByStation]);

  const selected = sorted?.find((s) => s.id === selectedId) ?? null;

  function toggleSort(key: SortKey) {
    if (sortKey === key) {
      setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(key);
      setSortDir('asc');
    }
  }

  return (
    <DashShell>
      <header className="mb-6 flex items-end justify-between">
        <div>
          <h2 className="text-2xl font-bold">Stations</h2>
          <p className="mt-1 text-sm text-fg-3">
            {sorted ? `${sorted.length} stations registered` : 'Loading…'}
          </p>
        </div>
      </header>

      {error && (
        <div className="mb-4 rounded-md border border-danger/40 bg-danger/5 px-3 py-2 text-xs text-danger">
          {error}
        </div>
      )}

      <ManageElsewhereHint topic="add a station, edit a tariff, or re-assign ownership" />

      <div className="overflow-hidden rounded-lg border border-rule bg-surface">
        <div className="hidden grid-cols-[1.5fr_1fr_1fr_1fr_28px] items-center gap-3 border-b border-rule px-4 py-2 text-[11px] font-semibold uppercase tracking-wide text-fg-3 md:grid">
          <SortHeader label="Station" sortKey="name" current={sortKey} dir={sortDir} onClick={toggleSort} />
          <SortHeader label="Connectors" sortKey="connectors" current={sortKey} dir={sortDir} onClick={toggleSort} />
          <SortHeader label="Live now" sortKey="live" current={sortKey} dir={sortDir} onClick={toggleSort} />
          <SortHeader label="฿ / kWh" sortKey="price" current={sortKey} dir={sortDir} onClick={toggleSort} />
          <span />
        </div>

        {sorted == null ? (
          Array.from({ length: 5 }).map((_, i) => (
            <div key={i} className="h-14 animate-pulse border-b border-rule bg-surface-2/50" />
          ))
        ) : sorted.length === 0 ? (
          <div className="px-4 py-8 text-center text-sm text-fg-3">
            No stations yet.
          </div>
        ) : (
          sorted.map((station) => {
            const live = liveByStation.get(station.id) ?? 0;
            return (
              <button
                key={station.id}
                onClick={() => setSelectedId(station.id)}
                className={cn(
                  'grid w-full grid-cols-[1.5fr_1fr_1fr_1fr_28px] items-center gap-3 border-b border-rule px-4 py-3 text-left text-sm transition last:border-b-0 hover:bg-surface-2',
                  selectedId === station.id && 'bg-accent-tint/40',
                )}
              >
                <div className="min-w-0">
                  <div className="truncate font-medium text-fg">{station.name}</div>
                  <div className="truncate text-[11px] text-fg-3">{station.address}</div>
                </div>
                <div className="flex items-center gap-1.5 text-fg-2">
                  <Plug size={13} />
                  <span className="tabular">{station.connectors.length}</span>
                </div>
                <div className="flex items-center gap-2">
                  <span
                    className={cn(
                      'inline-flex h-2 w-2 rounded-full',
                      live > 0 ? 'bg-success' : 'bg-fg-3/40',
                    )}
                  />
                  <span className="tabular text-fg-2">{live} live</span>
                </div>
                <div className="tabular text-fg-2">
                  {satangToBaht(station.tariff.pricePerKWhSatang)}
                </div>
                <ChevronRight size={14} className="text-fg-3" />
              </button>
            );
          })
        )}
      </div>

      <StationDetailPanel
        station={selected}
        statuses={statuses.filter((s) => s.stationId === selected?.id)}
        onClose={() => setSelectedId(null)}
      />
    </DashShell>
  );
}

interface SortHeaderProps {
  label: string;
  sortKey: SortKey;
  current: SortKey;
  dir: SortDir;
  onClick: (key: SortKey) => void;
}

function SortHeader({ label, sortKey, current, dir, onClick }: SortHeaderProps) {
  const active = sortKey === current;
  return (
    <button
      type="button"
      onClick={() => onClick(sortKey)}
      className={cn(
        'flex items-center gap-1 text-left',
        active ? 'text-fg' : 'text-fg-3 hover:text-fg-2',
      )}
    >
      {label}
      {active && (dir === 'asc' ? <ArrowUp size={11} /> : <ArrowDown size={11} />)}
    </button>
  );
}

// ---------------------------------------------------------------------------
// Slide-over detail panel
// ---------------------------------------------------------------------------

interface StationDetailPanelProps {
  station: Station | null;
  statuses: ConnectorLiveStatus[];
  onClose: () => void;
}

function StationDetailPanel({ station, statuses, onClose }: StationDetailPanelProps) {
  const [recent, setRecent] = useState<ChargingSession[] | null>(null);

  useEffect(() => {
    setRecent(null);
    if (!station) return;
    fetchSessions({ stationId: station.id, pageSize: 8 })
      .then(setRecent)
      .catch(() => setRecent([]));
  }, [station?.id]);

  if (!station) return null;

  return (
    <>
      <div
        className="fixed inset-0 z-30 bg-black/20"
        onClick={onClose}
        aria-hidden
      />
      <aside className="fixed inset-y-0 right-0 z-40 w-full max-w-md overflow-y-auto border-l border-rule bg-surface shadow-2xl">
        <header className="sticky top-0 flex items-center justify-between border-b border-rule bg-surface px-5 py-4">
          <div>
            <h3 className="text-base font-semibold">{station.name}</h3>
            <p className="text-[11px] text-fg-3">{station.address}</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-md border border-rule p-1 text-fg-3 hover:bg-surface-2"
            aria-label="Close"
          >
            <X size={14} />
          </button>
        </header>

        <section className="px-5 py-4">
          <h4 className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-fg-3">
            Connectors
          </h4>
          <div className="grid gap-2">
            {station.connectors.map((c) => {
              const live = statuses.find((s) => s.connectorId === c.id);
              return (
                <div
                  key={c.id}
                  className="flex items-center justify-between rounded-md border border-rule bg-surface-2 px-3 py-2 text-xs"
                >
                  <div>
                    <div className="font-medium text-fg">
                      {c.standard.toUpperCase()} · {c.powerKW} kW
                    </div>
                    <div className="text-fg-3">{c.id}</div>
                  </div>
                  <span
                    className={cn(
                      'rounded-full px-2 py-0.5 text-[10px] font-semibold',
                      statusBadgeClass(live?.status ?? 'Unavailable'),
                    )}
                  >
                    {live?.status ?? '—'}
                  </span>
                </div>
              );
            })}
          </div>
        </section>

        <section className="px-5 pb-4">
          <h4 className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-fg-3">
            Tariff
          </h4>
          <div className="grid grid-cols-2 gap-2">
            <div className="rounded-md border border-rule bg-surface-2 px-3 py-2 text-xs">
              <div className="text-fg-3">Per kWh</div>
              <div className="font-semibold text-fg tabular">
                {satangToBaht(station.tariff.pricePerKWhSatang)}
              </div>
            </div>
            <div className="rounded-md border border-rule bg-surface-2 px-3 py-2 text-xs">
              <div className="text-fg-3">Session fee</div>
              <div className="font-semibold text-fg tabular">
                {satangToBaht(station.tariff.sessionFeeSatang)}
              </div>
            </div>
          </div>
        </section>

        <section className="px-5 pb-6">
          <h4 className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-fg-3">
            Recent sessions
          </h4>
          {recent == null ? (
            <div className="h-32 animate-pulse rounded-md bg-surface-2" />
          ) : recent.length === 0 ? (
            <div className="rounded-md border border-rule bg-surface-2 px-3 py-4 text-center text-xs text-fg-3">
              No sessions yet.
            </div>
          ) : (
            <ul className="divide-y divide-rule rounded-md border border-rule bg-surface-2">
              {recent.map((s) => (
                <li key={s.id} className="px-3 py-2 text-xs">
                  <div className="flex items-center justify-between">
                    <span className="font-medium text-fg">
                      {s.startedAt.toLocaleString()}
                    </span>
                    <span className="font-semibold tabular text-fg">
                      {satangToBaht(s.costSatang)}
                    </span>
                  </div>
                  <div className="text-[11px] text-fg-3 tabular">
                    {kWh(s.energyKWh)} · {s.status}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </section>
      </aside>
    </>
  );
}

function statusBadgeClass(status: string): string {
  switch (status) {
    case 'Available':
      return 'bg-success/15 text-success';
    case 'Charging':
      return 'bg-accent/20 text-accent';
    case 'Faulted':
      return 'bg-danger/15 text-danger';
    case 'Unavailable':
      return 'bg-fg-3/15 text-fg-3';
    default:
      return 'bg-warning/15 text-warning';
  }
}
