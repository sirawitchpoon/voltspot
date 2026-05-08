'use client';

/**
 * Map view — geographic spread of the network with live status
 * colors. The Leaflet-driven map ships only on the client because
 * the leaflet package touches `window` at module load; we
 * dynamic-import it with `ssr: false` so the static export builds
 * cleanly.
 */
import { useEffect, useMemo, useState } from 'react';
import dynamic from 'next/dynamic';
import { X } from 'lucide-react';
import { DashShell } from '@/components/dash-shell';
import {
  fetchAllStations,
  subscribeConnectorStatuses,
} from '@/lib/queries';
import type {
  ConnectorLiveStatus,
  Station,
} from '@/lib/types';
import { satangToBaht } from '@/lib/satang';
import { cn } from '@/lib/utils';

const NetworkMap = dynamic(() => import('@/components/network-map'), {
  ssr: false,
  loading: () => (
    <div className="flex h-full items-center justify-center text-sm text-fg-3">
      Loading map…
    </div>
  ),
});

const STATUS_LEGEND: { color: string; label: string }[] = [
  { color: '#1e9b62', label: 'Available' },
  { color: '#2566db', label: 'Charging' },
  { color: '#d99a1f', label: 'Reserved / Suspended' },
  { color: '#cf2a2a', label: 'Faulted' },
  { color: '#7d7d7d', label: 'Unavailable' },
  { color: '#a8a297', label: 'No data' },
];

export default function MapPage() {
  const [stations, setStations] = useState<Station[] | null>(null);
  const [statuses, setStatuses] = useState<ConnectorLiveStatus[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<Station | null>(null);

  useEffect(() => {
    fetchAllStations()
      .then(setStations)
      .catch((e: Error) => setError(e.message));
    const unsub = subscribeConnectorStatuses(setStatuses);
    return unsub;
  }, []);

  const selectedStatuses = useMemo(
    () => (selected ? statuses.filter((s) => s.stationId === selected.id) : []),
    [statuses, selected],
  );

  return (
    <DashShell>
      <header className="mb-4 flex items-end justify-between">
        <div>
          <h2 className="text-2xl font-bold">Network map</h2>
          <p className="mt-1 text-sm text-fg-3">
            {stations ? `${stations.length} sites · live status updates as chargers report in` : 'Loading…'}
          </p>
        </div>
        <Legend />
      </header>

      {error && (
        <div className="mb-4 rounded-md border border-danger/40 bg-danger/5 px-3 py-2 text-xs text-danger">
          {error}
        </div>
      )}

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-[1fr_320px]">
        <div className="h-[68vh] overflow-hidden rounded-lg border border-rule bg-surface">
          {stations == null ? (
            <div className="flex h-full items-center justify-center text-sm text-fg-3">
              Loading stations…
            </div>
          ) : (
            <NetworkMap
              stations={stations}
              statuses={statuses}
              onSelect={(s) => setSelected(s)}
            />
          )}
        </div>

        <SidePanel
          station={selected}
          statuses={selectedStatuses}
          onClose={() => setSelected(null)}
        />
      </div>
    </DashShell>
  );
}

function Legend() {
  return (
    <div className="hidden flex-wrap items-center gap-3 rounded-md border border-rule bg-surface px-3 py-1.5 text-[11px] md:flex">
      {STATUS_LEGEND.map((entry) => (
        <span key={entry.label} className="flex items-center gap-1.5 text-fg-2">
          <span
            className="inline-block h-2.5 w-2.5 rounded-full ring-2 ring-white"
            style={{ background: entry.color }}
          />
          {entry.label}
        </span>
      ))}
    </div>
  );
}

interface SidePanelProps {
  station: Station | null;
  statuses: ConnectorLiveStatus[];
  onClose: () => void;
}

function SidePanel({ station, statuses, onClose }: SidePanelProps) {
  if (!station) {
    return (
      <aside className="hidden h-[68vh] flex-col items-center justify-center rounded-lg border border-dashed border-rule bg-surface text-center text-xs text-fg-3 lg:flex">
        <span className="px-6">Select a marker to see connector status, tariff, and recent activity.</span>
      </aside>
    );
  }

  return (
    <aside className="relative h-[68vh] overflow-y-auto rounded-lg border border-rule bg-surface">
      <header className="sticky top-0 flex items-start justify-between border-b border-rule bg-surface px-4 py-3">
        <div className="min-w-0">
          <h3 className="truncate text-sm font-semibold">{station.name}</h3>
          <p className="truncate text-[11px] text-fg-3">{station.address}</p>
        </div>
        <button
          type="button"
          onClick={onClose}
          aria-label="Close"
          className="ml-2 rounded-md border border-rule p-1 text-fg-3 hover:bg-surface-2"
        >
          <X size={14} />
        </button>
      </header>

      <section className="px-4 py-3">
        <h4 className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-fg-3">
          Connectors
        </h4>
        <div className="space-y-2">
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
                  <div className="text-fg-3 tabular">{c.id}</div>
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

      <section className="px-4 pb-4">
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
    </aside>
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
