package server

import (
	"crypto/rand"
	"encoding/hex"
	"sync"
	"time"
)

// pendingStart links a RemoteStartTransaction we sent to the charger
// with the iOS user who initiated it. The charger comes back with
// StartTransaction(idTag=<our generated id>) — looking up the entry
// by that idTag tells us which Firebase uid + stationId + connectorId
// to stamp on the new /sessions doc.
//
// This is the only mechanism that lets the iOS "my charging history"
// query (where userId == currentUid) include sessions started from
// the app — because OCPP doesn't carry the originating identity
// past the charger boundary.
//
// Stored in-memory because:
//   1. Min-instances=1 on Cloud Run ⇒ a single Gateway instance owns
//      a charger's WebSocket, and therefore both the request and
//      the response.
//   2. The window from RemoteStartTransaction Accepted to
//      StartTransaction is < 30s in practice (charger latency, plug
//      verification, immobiliser unlocks).
//   3. A short TTL (5 min) drops abandoned attempts before the map
//      grows.
//
// When we ever go multi-instance, this moves into Firestore + a
// short-lived doc keyed off idTag, with the same TTL semantics.
type pendingStart struct {
	idTag       string
	userID      string
	stationID   string
	connectorID int
	expiresAt   time.Time
}

// PendingStarts is the registry the REST handler writes to before
// issuing RemoteStartTransaction, and that the AppDelegate reads
// from when the matching StartTransaction arrives.
//
// Safe for concurrent use. The mutex is held only briefly so a
// burst of remote starts won't bottleneck.
type PendingStarts struct {
	mu      sync.Mutex
	byIDTag map[string]*pendingStart
	now     func() time.Time // override for tests
	ttl     time.Duration
}

// NewPendingStarts creates a registry with the given TTL. Pass 5*time.Minute
// for production; tests can override via fields.
func NewPendingStarts(ttl time.Duration) *PendingStarts {
	if ttl <= 0 {
		ttl = 5 * time.Minute
	}
	return &PendingStarts{
		byIDTag: make(map[string]*pendingStart),
		now:     time.Now,
		ttl:     ttl,
	}
}

// Issue registers a new pending-start for a user and returns the
// idTag the REST handler should pass to the charger. The idTag is a
// 16-character hex string (8 random bytes) — well below the OCPP
// 20-char idTag cap, and collision-resistant for any practical
// number of in-flight starts.
func (p *PendingStarts) Issue(userID, stationID string, connectorID int) (string, error) {
	idTag, err := newPendingIDTag()
	if err != nil {
		return "", err
	}
	expires := p.now().Add(p.ttl)

	p.mu.Lock()
	defer p.mu.Unlock()
	p.byIDTag[idTag] = &pendingStart{
		idTag:       idTag,
		userID:      userID,
		stationID:   stationID,
		connectorID: connectorID,
		expiresAt:   expires,
	}
	return idTag, nil
}

// Claim removes and returns the pending start matching idTag, or
// nil if none is found or the entry has expired. Each entry can be
// claimed exactly once — protects against a charger replaying an
// old StartTransaction.
func (p *PendingStarts) Claim(idTag string) *PendingClaim {
	p.mu.Lock()
	defer p.mu.Unlock()
	ps, ok := p.byIDTag[idTag]
	if !ok {
		return nil
	}
	delete(p.byIDTag, idTag)
	if p.now().After(ps.expiresAt) {
		return nil
	}
	return &PendingClaim{
		UserID:      ps.userID,
		StationID:   ps.stationID,
		ConnectorID: ps.connectorID,
	}
}

// PendingClaim is the public form of a successful Claim — only the
// fields the AppDelegate actually consumes.
type PendingClaim struct {
	UserID      string
	StationID   string
	ConnectorID int
}

// EvictExpired removes all entries past their TTL. Call from a
// background goroutine so the map doesn't grow with abandoned
// remote-start attempts.
func (p *PendingStarts) EvictExpired() {
	now := p.now()
	p.mu.Lock()
	defer p.mu.Unlock()
	for id, ps := range p.byIDTag {
		if now.After(ps.expiresAt) {
			delete(p.byIDTag, id)
		}
	}
}

// Len reports the number of active pending-starts. Exposed for
// /readyz diagnostics + tests.
func (p *PendingStarts) Len() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	return len(p.byIDTag)
}

// newPendingIDTag returns 16 hex chars from /dev/urandom. Same
// approach as Conn.newUniqueID but separate so the constants don't
// drift accidentally.
func newPendingIDTag() (string, error) {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return hex.EncodeToString(b[:]), nil
}
