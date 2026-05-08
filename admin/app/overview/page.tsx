'use client';

/**
 * Overview — the at-a-glance landing page. Four KPI cards driven by:
 *   - sessions today (status filter, startTime today)
 *   - chargers online (connector_status where status != Faulted/Unavailable)
 *   - revenue today (sum of costSatang for completed sessions today)
 *   - total stations
 *
 * Plus a 30-day daily revenue sparkline (Recharts) so the founder
 * can eyeball trend without leaving the page.
 *
 * Loads happen via three independent listeners — `recentSessions`
 * (cheap snapshot covering today + month aggregate), `connector_status`
 * (live network health), and a one-shot `fetchAllStations` for the
 * count tile. Listener fan-out is deliberate: each one writes its
 * own piece of state so we don't block the whole page on the slowest.
 */
import { useEffect, useMemo, useState } from 'react';
import {
  Bolt,
  Building2,
  CircleDollarSign,
  Activity,
} from 'lucide-react';
import {
  ResponsiveContainer,
  BarChart,
  Bar,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { DashShell } from '@/components/dash-shell';
import { KpiCard } from '@/components/kpi-card';
import {
  fetchAllStations,
  subscribeConnectorStatuses,
  subscribeRecentSessions,
} from '@/lib/queries';
import type {
  ChargingSession,
  ConnectorLiveStatus,
  Station,
} from '@/lib/types';
import { compactInt, satangToBaht } from '@/lib/satang';

export default function OverviewPage() {
  const [sessions, setSessions] = useState<ChargingSession[] | null>(null);
  const [statuses, setStatuses] = useState<ConnectorLiveStatus[] | null>(null);
  const [stations, setStations] = useState<Station[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    // Pull a generous window so today's cards + the 30-day chart can
    // both come from the same listener without re-querying.
    const unsubSessions = subscribeRecentSessions(500, setSessions);
    const unsubStatuses = subscribeConnectorStatuses(setStatuses);

    fetchAllStations()
      .then(setStations)
      .catch((e: Error) => setError(e.message));

    return () => {
      unsubSessions();
      unsubStatuses();
    };
  }, []);

  const today = useMemo(() => boundsToday(), []);
  const sessionsToday = useMemo(
    () => (sessions ?? []).filter((s) => s.startedAt >= today.from && s.startedAt < today.to),
    [sessions, today],
  );
  const revenueTodaySatang = sessionsToday.reduce((acc, s) => acc + s.costSatang, 0);

  const onlineCount = useMemo(() => {
    if (!statuses) return null;
    return statuses.filter(
      (s) => s.status !== 'Faulted' && s.status !== 'Unavailable',
    ).length;
  }, [statuses]);

  const dailyChart = useMemo(
    () => buildDailyRevenueSeries(sessions ?? [], 30),
    [sessions],
  );

  return (
    <DashShell>
      <div className="mb-6 flex items-end justify-between">
        <div>
          <h2 className="text-2xl font-bold">Overview</h2>
          <p className="mt-1 text-sm text-fg-3">
            Live network snapshot · updates in real time as sessions and chargers report in.
          </p>
        </div>
      </div>

      {error && (
        <div className="mb-4 rounded-md border border-danger/40 bg-danger/5 px-3 py-2 text-xs text-danger">
          {error}
        </div>
      )}

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <KpiCard
          label="Sessions today"
          value={sessions == null ? '—' : compactInt(sessionsToday.length)}
          icon={Bolt}
          loading={sessions == null}
        />
        <KpiCard
          label="Chargers online"
          value={onlineCount == null ? '—' : compactInt(onlineCount)}
          icon={Activity}
          loading={statuses == null}
          hint={statuses ? `of ${statuses.length} reporting` : undefined}
        />
        <KpiCard
          label="Revenue today"
          value={sessions == null ? '—' : satangToBaht(revenueTodaySatang)}
          icon={CircleDollarSign}
          accent
          loading={sessions == null}
        />
        <KpiCard
          label="Stations"
          value={stations == null ? '—' : compactInt(stations.length)}
          icon={Building2}
          loading={stations == null}
        />
      </div>

      <section className="mt-6 rounded-lg border border-rule bg-surface p-4">
        <div className="mb-4 flex items-center justify-between">
          <h3 className="text-sm font-semibold">Daily revenue · last 30 days</h3>
          <span className="text-[11px] text-fg-3 tabular">
            {sessions == null ? '—' : satangToBaht(monthGross(dailyChart))} total
          </span>
        </div>
        {sessions == null ? (
          <div className="h-40 animate-pulse rounded-md bg-surface-2" />
        ) : (
          <ResponsiveContainer width="100%" height={160}>
            <BarChart data={dailyChart}>
              <XAxis dataKey="label" hide />
              <YAxis hide />
              <Tooltip
                cursor={{ fill: 'hsl(var(--surface-2))' }}
                contentStyle={{
                  fontSize: 12,
                  borderRadius: 8,
                  border: '1px solid hsl(var(--rule))',
                  background: 'hsl(var(--surface))',
                }}
                formatter={(value: number) => [satangToBaht(value), 'Revenue']}
                labelFormatter={(l) => `Day ${l}`}
              />
              <Bar
                dataKey="satang"
                fill="hsl(var(--accent))"
                radius={[3, 3, 0, 0]}
              />
            </BarChart>
          </ResponsiveContainer>
        )}
      </section>
    </DashShell>
  );
}

function boundsToday(): { from: Date; to: Date } {
  const from = new Date();
  from.setHours(0, 0, 0, 0);
  const to = new Date(from);
  to.setDate(to.getDate() + 1);
  return { from, to };
}

interface DailyBucket {
  label: string;
  satang: number;
}

function buildDailyRevenueSeries(sessions: ChargingSession[], days: number): DailyBucket[] {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const out: DailyBucket[] = [];
  for (let i = days - 1; i >= 0; i--) {
    const day = new Date(today);
    day.setDate(today.getDate() - i);
    out.push({ label: `${day.getDate()}`, satang: 0 });
  }
  for (const s of sessions) {
    const day = new Date(s.startedAt);
    day.setHours(0, 0, 0, 0);
    const offset = Math.round((today.getTime() - day.getTime()) / 86_400_000);
    if (offset < 0 || offset >= days) continue;
    out[days - 1 - offset].satang += s.costSatang;
  }
  return out;
}

function monthGross(buckets: DailyBucket[]): number {
  return buckets.reduce((acc, b) => acc + b.satang, 0);
}
