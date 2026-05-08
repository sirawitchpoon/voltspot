'use client';

import { type LucideIcon } from 'lucide-react';
import { cn } from '@/lib/utils';

/// Compact KPI card. Mirrors `Voltspot/Voltspot/Presentation/Common/StatTile.swift`
/// information density — title at top, big tabular number, optional unit
/// suffix, and an icon corner. `loading` swaps the value for a placeholder.
export interface KpiCardProps {
  label: string;
  value: string;
  unit?: string;
  icon?: LucideIcon;
  accent?: boolean;
  loading?: boolean;
  hint?: string;
}

export function KpiCard({ label, value, unit, icon: Icon, accent, loading, hint }: KpiCardProps) {
  return (
    <div
      className={cn(
        'rounded-lg border border-rule bg-surface p-4',
        accent && 'bg-accent-tint',
      )}
    >
      <div className="flex items-center justify-between">
        <span className="text-[11px] font-medium uppercase tracking-wide text-fg-3">
          {label}
        </span>
        {Icon && <Icon size={14} className={cn('text-fg-3', accent && 'text-accent')} />}
      </div>
      <div className="mt-2 flex items-baseline gap-1.5">
        <span
          className={cn(
            'text-2xl font-semibold tabular',
            accent ? 'text-accent' : 'text-fg',
            loading && 'animate-pulse text-fg-3',
          )}
        >
          {loading ? '—' : value}
        </span>
        {unit && !loading && (
          <span className="text-xs font-medium text-fg-3">{unit}</span>
        )}
      </div>
      {hint && <div className="mt-1 text-[11px] text-fg-3">{hint}</div>}
    </div>
  );
}
