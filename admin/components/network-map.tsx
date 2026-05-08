'use client';

/**
 * Live network map. Imported via dynamic(...{ ssr: false }) from
 * the page wrapper so Leaflet — which touches `window` at module
 * load — never runs during the static export pre-render. Tiles come
 * from OpenStreetMap (free, no key needed) so we don't introduce
 * a recurring dependency.
 *
 * Markers re-color in real time as the connector_status snapshot
 * arrives, which is the demo's headline "wow" moment: flip a doc in
 * the Firebase Console and the dot changes color within ~1 second.
 */
import { useMemo } from 'react';
import {
  MapContainer,
  TileLayer,
  CircleMarker,
  Tooltip as LeafletTooltip,
} from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import type {
  ChargePointStatus,
  ConnectorLiveStatus,
  Station,
} from '@/lib/types';

interface NetworkMapProps {
  stations: Station[];
  statuses: ConnectorLiveStatus[];
  onSelect?: (station: Station) => void;
}

// Roughly central Thailand — frames Bangkok + Korat + Chiang Mai +
// the Gulf coast at zoom 5.
const DEFAULT_CENTER: [number, number] = [13.85, 100.6];
const DEFAULT_ZOOM = 6;

export default function NetworkMap({ stations, statuses, onSelect }: NetworkMapProps) {
  const statusByStation = useMemo(() => {
    const map = new Map<string, ConnectorLiveStatus[]>();
    for (const s of statuses) {
      const list = map.get(s.stationId) ?? [];
      list.push(s);
      map.set(s.stationId, list);
    }
    return map;
  }, [statuses]);

  return (
    <MapContainer
      center={DEFAULT_CENTER}
      zoom={DEFAULT_ZOOM}
      scrollWheelZoom
      className="h-full w-full rounded-lg"
      style={{ background: 'hsl(var(--surface-2))' }}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {stations.map((station) => {
        const stationStatuses = statusByStation.get(station.id) ?? [];
        const aggregate = aggregateStatus(stationStatuses);
        return (
          <CircleMarker
            key={station.id}
            center={[station.latitude, station.longitude]}
            radius={9}
            pathOptions={{
              color: '#fff',
              weight: 2,
              fillColor: STATUS_FILL[aggregate],
              fillOpacity: 0.9,
            }}
            eventHandlers={{ click: () => onSelect?.(station) }}
          >
            <LeafletTooltip direction="top" offset={[0, -6]} opacity={1}>
              <div className="text-xs">
                <div className="font-semibold">{station.name}</div>
                <div className="text-fg-3">{aggregate}</div>
              </div>
            </LeafletTooltip>
          </CircleMarker>
        );
      })}
    </MapContainer>
  );
}

/// Resolves the dot color from the worst connector state at the
/// station — Faulted dominates (orange/red), then Unavailable
/// (gray), then Charging (blue), then Available (green). If the
/// station has no live status reports at all we paint it muted so
/// the operator can spot "we never heard from this site" quickly.
function aggregateStatus(statuses: ConnectorLiveStatus[]): ChargePointStatus | 'Unknown' {
  if (statuses.length === 0) return 'Unknown';
  const PRIORITY: ChargePointStatus[] = [
    'Faulted',
    'Unavailable',
    'SuspendedEV',
    'SuspendedEVSE',
    'Preparing',
    'Reserved',
    'Charging',
    'Finishing',
    'Available',
  ];
  for (const target of PRIORITY) {
    if (statuses.some((s) => s.status === target)) return target;
  }
  return statuses[0].status;
}

const STATUS_FILL: Record<ChargePointStatus | 'Unknown', string> = {
  Available: '#1e9b62',
  Charging: '#2566db',
  Preparing: '#2566db',
  Finishing: '#2566db',
  Reserved: '#d99a1f',
  SuspendedEV: '#d99a1f',
  SuspendedEVSE: '#d99a1f',
  Faulted: '#cf2a2a',
  Unavailable: '#7d7d7d',
  Unknown: '#a8a297',
};
