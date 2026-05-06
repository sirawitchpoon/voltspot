package server

import (
	"sync"
	"testing"
	"time"
)

func TestPendingStarts_IssueClaim(t *testing.T) {
	p := NewPendingStarts(5 * time.Minute)
	idTag, err := p.Issue("uid-123", "stn-bkk-01", 1)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}
	if len(idTag) != 16 {
		t.Errorf("idTag len = %d, want 16 hex chars", len(idTag))
	}
	c := p.Claim(idTag)
	if c == nil {
		t.Fatal("Claim returned nil")
	}
	if c.UserID != "uid-123" || c.StationID != "stn-bkk-01" || c.ConnectorID != 1 {
		t.Errorf("Claim returned %+v", c)
	}
	// Second claim must miss — protects against replay.
	if again := p.Claim(idTag); again != nil {
		t.Error("second Claim should return nil")
	}
}

func TestPendingStarts_ExpiredEntriesIgnored(t *testing.T) {
	p := NewPendingStarts(time.Minute)
	now := time.Now()
	p.now = func() time.Time { return now }

	idTag, _ := p.Issue("uid", "stn", 1)
	// Fast-forward past expiry.
	p.now = func() time.Time { return now.Add(2 * time.Minute) }

	if c := p.Claim(idTag); c != nil {
		t.Error("expired entry should not Claim")
	}
}

func TestPendingStarts_EvictExpired(t *testing.T) {
	p := NewPendingStarts(time.Minute)
	now := time.Now()
	p.now = func() time.Time { return now }

	for i := 0; i < 5; i++ {
		_, _ = p.Issue("uid", "stn", 1)
	}
	if p.Len() != 5 {
		t.Errorf("Len after 5 issues = %d", p.Len())
	}

	p.now = func() time.Time { return now.Add(2 * time.Minute) }
	p.EvictExpired()
	if p.Len() != 0 {
		t.Errorf("Len after eviction = %d", p.Len())
	}
}

func TestPendingStarts_ConcurrentSafe(t *testing.T) {
	p := NewPendingStarts(5 * time.Minute)
	var wg sync.WaitGroup
	for g := 0; g < 16; g++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < 100; i++ {
				idTag, err := p.Issue("uid", "stn", i%4)
				if err != nil {
					t.Errorf("Issue: %v", err)
					return
				}
				if c := p.Claim(idTag); c == nil {
					t.Errorf("immediate Claim returned nil")
					return
				}
			}
		}()
	}
	wg.Wait()
	if p.Len() != 0 {
		t.Errorf("Len after all issued+claimed = %d", p.Len())
	}
}
