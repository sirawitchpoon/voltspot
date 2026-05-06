package transactions

import (
	"sync"
	"testing"
)

func TestAllocatorMonotonic(t *testing.T) {
	a := New(0)
	for i := 1; i <= 100; i++ {
		if got := a.Next(); got != i {
			t.Fatalf("Next() #%d = %d, want %d", i, got, i)
		}
	}
}

func TestAllocatorRespectsFloor(t *testing.T) {
	a := New(99)
	if got := a.Next(); got != 100 {
		t.Errorf("Next after floor=99 = %d, want 100", got)
	}
}

func TestAllocatorConcurrent(t *testing.T) {
	a := New(0)
	const N = 1000
	const goroutines = 16
	got := sync.Map{}

	var wg sync.WaitGroup
	for g := 0; g < goroutines; g++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < N; i++ {
				id := a.Next()
				if _, dup := got.LoadOrStore(id, true); dup {
					t.Errorf("duplicate id %d", id)
				}
			}
		}()
	}
	wg.Wait()

	count := 0
	got.Range(func(_, _ any) bool { count++; return true })
	if count != goroutines*N {
		t.Errorf("got %d unique ids, want %d", count, goroutines*N)
	}
}
