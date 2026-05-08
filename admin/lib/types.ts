/**
 * Wire types mirroring `Voltspot/Voltspot/Domain/Entities/*.swift`.
 * Field names MUST stay in lockstep with the Swift definitions —
 * a typo here means silent decode failures because Firestore stores
 * data with whatever names the writer used.
 *
 * Money is integer satang (CLAUDE.md invariant). Convert to baht for
 * display only via `lib/satang.ts`. Never use `number` for cost
 * fields — JS numbers lose precision past 2^53 satang (= ~฿90 trillion)
 * which is fine in absolute terms, but the type discipline matches
 * the Swift `Int` rule and prevents accidental floating-point drift.
 */
import type { Timestamp } from 'firebase/firestore';

/** Mirrors `ConnectorKind` (Swift enum). */
export type ConnectorKind = 'ev' | 'drone';

/** Mirrors `ConnectorStandard`. Add cases as the iOS enum grows. */
export type ConnectorStandard =
  | 'type1'
  | 'type2'
  | 'ccs1'
  | 'ccs2'
  | 'chademo'
  | 'gbT'
  | 'droneXT60'
  | 'droneXT90'
  | 'droneCustom';

/**
 * Mirrors `ConnectorStatus`. Distinct from the OCPP charge-point
 * status enum used in `connector_status/{key}.status` — keep both
 * clear in calling code.
 */
export type ConnectorStatus =
  | 'available'
  | 'occupied'
  | 'reserved'
  | 'faulted'
  | 'offline';

export interface Connector {
  id: string;
  kind: ConnectorKind;
  standard: ConnectorStandard;
  powerKW: number;
  status: ConnectorStatus;
}

export interface Tariff {
  pricePerKWhSatang: number;
  sessionFeeSatang: number;
}

export interface Station {
  id: string;
  name: string;
  address: string;
  latitude: number;
  longitude: number;
  connectors: Connector[];
  tariff: Tariff;
  supportsDrones: boolean;
  partnerId: string | null;
}

export type SessionStatus = 'active' | 'completed' | 'failed' | 'interrupted';

export interface ChargingSession {
  id: string;
  stationId: string;
  connectorId: string;
  userId: string | null;
  partnerId: string | null;
  status: SessionStatus;
  startedAt: Date;
  endedAt: Date | null;
  energyKWh: number;
  costSatang: number;
}

/** Live connector state written by the OCPP Gateway. */
export type ChargePointStatus =
  | 'Available'
  | 'Preparing'
  | 'Charging'
  | 'SuspendedEV'
  | 'SuspendedEVSE'
  | 'Finishing'
  | 'Reserved'
  | 'Unavailable'
  | 'Faulted';

export interface ConnectorLiveStatus {
  /** `{stationId}_{connectorId}` — Firestore doc id. */
  key: string;
  stationId: string;
  connectorId: string;
  status: ChargePointStatus;
  errorCode: string;
  info: string | null;
  activeTransactionId: number | null;
  lastUpdated: Date;
}

// ---------------------------------------------------------------------------
// Decoders — accept Firestore document data (with Timestamps) and return the
// plain TS shapes above. Mirror the Swift `decodeSession` / `decode(document:)`
// patterns in RealStationRepository and RealSessionRepository.
// ---------------------------------------------------------------------------

type Doc = Record<string, unknown>;

function tsToDate(v: unknown): Date | null {
  if (v == null) return null;
  if (v instanceof Date) return v;
  if (typeof (v as Timestamp).toDate === 'function') {
    return (v as Timestamp).toDate();
  }
  return null;
}

function asString(v: unknown): string | null {
  return typeof v === 'string' ? v : null;
}

function asNumber(v: unknown): number {
  if (typeof v === 'number') return v;
  if (typeof v === 'bigint') return Number(v);
  return 0;
}

export function decodeStation(id: string, data: Doc): Station | null {
  const name = asString(data.name);
  const address = asString(data.address);
  if (!name || !address) return null;

  let latitude = 0;
  let longitude = 0;
  const loc = data.location as { latitude?: number; longitude?: number } | undefined;
  if (loc && typeof loc.latitude === 'number' && typeof loc.longitude === 'number') {
    latitude = loc.latitude;
    longitude = loc.longitude;
  } else if (typeof data.latitude === 'number' && typeof data.longitude === 'number') {
    latitude = data.latitude;
    longitude = data.longitude;
  } else {
    return null;
  }

  const tariffRaw = (data.tariff as Doc) ?? {};
  const tariff: Tariff = {
    pricePerKWhSatang: asNumber(tariffRaw.pricePerKWhSatang),
    sessionFeeSatang: asNumber(tariffRaw.sessionFeeSatang),
  };

  const connectorsRaw = Array.isArray(data.connectors) ? (data.connectors as Doc[]) : [];
  const connectors: Connector[] = connectorsRaw
    .map((c): Connector | null => {
      const cId = asString(c.id);
      const kind = asString(c.kind) as ConnectorKind | null;
      const standard = asString(c.standard) as ConnectorStandard | null;
      const status = asString(c.status) as ConnectorStatus | null;
      if (!cId || !kind || !standard || !status) return null;
      return {
        id: cId,
        kind,
        standard,
        powerKW: asNumber(c.powerKW),
        status,
      };
    })
    .filter((c): c is Connector => c !== null);

  return {
    id,
    name,
    address,
    latitude,
    longitude,
    connectors,
    tariff,
    supportsDrones: Boolean(data.supportsDrones),
    partnerId: asString(data.partnerId),
  };
}

export function decodeSession(id: string, data: Doc): ChargingSession | null {
  const stationId = asString(data.stationId);
  if (!stationId) return null;

  let connectorId: string;
  if (typeof data.connectorId === 'string') connectorId = data.connectorId;
  else if (typeof data.connectorId === 'number') connectorId = String(data.connectorId);
  else return null;

  return {
    id,
    stationId,
    connectorId,
    userId: asString(data.userId),
    partnerId: asString(data.partnerId),
    status: ((asString(data.status) as SessionStatus) ?? 'completed'),
    startedAt: tsToDate(data.startTime) ?? new Date(0),
    endedAt: tsToDate(data.endTime),
    energyKWh: asNumber(data.energyKWh),
    costSatang: asNumber(data.costSatang),
  };
}

export function decodeConnectorLive(key: string, data: Doc): ConnectorLiveStatus | null {
  const parts = key.split('_');
  if (parts.length !== 2) return null;
  const [stationId, connectorId] = parts;
  return {
    key,
    stationId,
    connectorId,
    status: ((asString(data.status) as ChargePointStatus) ?? 'Unavailable'),
    errorCode: asString(data.errorCode) ?? 'NoError',
    info: asString(data.info),
    activeTransactionId:
      typeof data.activeTransactionId === 'number' ? data.activeTransactionId : null,
    lastUpdated: tsToDate(data.lastUpdated) ?? new Date(0),
  };
}
