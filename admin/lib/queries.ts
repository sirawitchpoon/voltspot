'use client';

/**
 * Typed Firestore queries for admin views. Two flavours:
 *
 *   - `fetch...` returns a one-shot Promise (use for table pages
 *     where pull-to-refresh is the update model).
 *   - `subscribe...` returns an unsubscribe function and pushes
 *     decoded results into a callback (use for the Map and the
 *     Sessions feed where realtime "wow" matters).
 *
 * Each query maps onto a Firestore composite index defined in
 * `deploy/firestore.indexes.json`. If you add a new query, add the
 * index too — the SDK will throw a console error pointing at the
 * required index URL otherwise.
 */
import {
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  onSnapshot,
  orderBy,
  query,
  where,
  Timestamp,
  type DocumentData,
  type QueryDocumentSnapshot,
  type Unsubscribe,
} from 'firebase/firestore';
import { firestore } from './firebase';
import {
  decodeConnectorLive,
  decodeSession,
  decodeStation,
  type ChargingSession,
  type ConnectorLiveStatus,
  type SessionStatus,
  type Station,
} from './types';

// ---------------------------------------------------------------------------
// Stations — full network read. The volume here is small (50K at scale, far
// less in pre-MVP) so a single getDocs is fine; we'll switch to paginated
// queries once we cross ~5K stations.
// ---------------------------------------------------------------------------

export async function fetchAllStations(): Promise<Station[]> {
  const snap = await getDocs(query(collection(firestore(), 'stations'), orderBy('name')));
  return decodeAll(snap.docs, decodeStation);
}

export async function fetchStation(id: string): Promise<Station | null> {
  const snap = await getDoc(doc(firestore(), 'stations', id));
  if (!snap.exists()) return null;
  return decodeStation(snap.id, snap.data() as DocumentData);
}

// ---------------------------------------------------------------------------
// Connector status — live state per (station, connector). Keyed by
// `{stationId}_{connectorId}` per the Gateway writer convention.
// Backed by a default field index; no composite needed.
// ---------------------------------------------------------------------------

export function subscribeConnectorStatuses(
  onUpdate: (statuses: ConnectorLiveStatus[]) => void,
): Unsubscribe {
  return onSnapshot(collection(firestore(), 'connector_status'), (snap) => {
    const decoded = decodeAll(snap.docs, decodeConnectorLive);
    onUpdate(decoded);
  });
}

// ---------------------------------------------------------------------------
// Sessions — admin feed. Filters can mix {status, stationId, dateRange};
// Firestore needs the right composite index for each combination — for v1
// we keep the surface narrow (just date-windowed by startTime) and let the
// caller add additional .where filters in-page after the index is in place.
// ---------------------------------------------------------------------------

export interface SessionsFilter {
  from?: Date;
  to?: Date;
  stationId?: string;
  status?: SessionStatus;
  pageSize?: number;
}

export async function fetchSessions(filter: SessionsFilter = {}): Promise<ChargingSession[]> {
  const constraints = [];
  if (filter.stationId) {
    constraints.push(where('stationId', '==', filter.stationId));
  }
  if (filter.status) {
    constraints.push(where('status', '==', filter.status));
  }
  if (filter.from) {
    constraints.push(where('startTime', '>=', Timestamp.fromDate(filter.from)));
  }
  if (filter.to) {
    constraints.push(where('startTime', '<', Timestamp.fromDate(filter.to)));
  }
  constraints.push(orderBy('startTime', 'desc'));
  constraints.push(limit(filter.pageSize ?? 50));

  const snap = await getDocs(query(collection(firestore(), 'sessions'), ...constraints));
  return decodeAll(snap.docs, decodeSession);
}

/// Live feed for the Overview/Sessions screens — pushes new sessions as
/// they're created. Orders by startTime desc + caps at pageSize so a
/// noisy day doesn't blow up the listener.
export function subscribeRecentSessions(
  pageSize: number,
  onUpdate: (sessions: ChargingSession[]) => void,
): Unsubscribe {
  const q = query(
    collection(firestore(), 'sessions'),
    orderBy('startTime', 'desc'),
    limit(pageSize),
  );
  return onSnapshot(q, (snap) => {
    onUpdate(decodeAll(snap.docs, decodeSession));
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function decodeAll<T>(
  docs: QueryDocumentSnapshot<DocumentData>[],
  decoder: (id: string, data: DocumentData) => T | null,
): T[] {
  const out: T[] = [];
  for (const d of docs) {
    const decoded = decoder(d.id, d.data());
    if (decoded) out.push(decoded);
  }
  return out;
}
