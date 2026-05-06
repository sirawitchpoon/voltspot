package server

import (
	"crypto/rand"
	"encoding/hex"
)

// newUniqueID returns a 32-hex-character random string suitable for
// use as the OCPP-J uniqueId. The spec doesn't constrain format
// beyond "string", but real-world chargers have been observed to
// truncate IDs longer than 36 chars, so 32 is safely under the cap.
//
// Uses crypto/rand so two simultaneous Calls from this Gateway can
// never collide — math/rand seeded once would risk a clash on rapid
// successive calls.
func newUniqueID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		// rand.Read on darwin/linux only fails on pathological errors
		// (closed /dev/urandom). If it ever does, we'd rather panic
		// than silently emit a non-unique id.
		panic("server: rand.Read failed: " + err.Error())
	}
	return hex.EncodeToString(b[:])
}
