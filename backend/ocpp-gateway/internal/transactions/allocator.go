// Package transactions allocates OCPP transaction IDs.
//
// Per OCPP 1.6 spec §5.18 the Central System assigns the
// transactionId in the StartTransaction response. The id must be
// unique across the lifetime of the Central System. We use a
// monotonic counter per Gateway instance, seeded from the highest
// transaction id found in Firestore at startup so restarts don't
// collide with sessions already in flight.
package transactions

import (
	"sync/atomic"
)

// Allocator hands out monotonic int32 transaction IDs. Cloud Run can
// run multiple Gateway instances concurrently — each instance gets
// its own non-overlapping ID range via the Stride+Offset constructor.
// For MVP (min-instances=1) we use Single which is the simplest
// possible counter.
type Allocator struct {
	next atomic.Int64
}

// New returns an allocator whose first call to Next returns floor+1.
// floor should be the maximum transactionId already persisted in
// Firestore so we never reissue an id used by an earlier instance.
func New(floor int64) *Allocator {
	a := &Allocator{}
	a.next.Store(floor)
	return a
}

// Next returns the next transaction id. Safe for concurrent use.
//
// OCPP 1.6 transactionId is "an integer", but real chargers commonly
// store it in a 32-bit field. We cap at math.MaxInt32 with a safety
// margin so we don't roll over silently — the operator will see the
// allocator panic well before that point in normal operation. For
// MVP (a few sessions per minute) this never matters, but it'd be
// painful to discover in year 5.
func (a *Allocator) Next() int {
	id := a.next.Add(1)
	const maxSafe = 2_000_000_000 // ~MaxInt32 with headroom
	if id >= maxSafe {
		panic("transactions: allocator near int32 ceiling — restart with reset floor")
	}
	return int(id)
}

// Peek returns the highest id allocated so far without advancing.
// Useful for periodic Firestore checkpoints if we ever switch to
// resilient cross-instance allocation.
func (a *Allocator) Peek() int64 {
	return a.next.Load()
}
