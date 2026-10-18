package msruntime

import (
	"reflect"
	"sort"
	"testing"
)

func TestPriorityQueueDequeueMatchesStableOrder(t *testing.T) {
	type item struct{ priority, id int }
	ctx := RootExecution()
	for _, size := range []int{0, 1, 2, 3, 7, 8, 16, 255, 256, 257, 1024, 4097} {
		q := NewPriorityQueue(func(_ *Execution, a, b item) int { return a.priority - b.priority }, None[int]())
		want := make([]item, size)
		for i := range want {
			want[i] = item{(i * 7919) % 17, i}
			PriorityQueue_Enqueue(ctx, q, want[i])
		}
		sort.SliceStable(want, func(i, j int) bool { return want[i].priority < want[j].priority })
		for i, value := range want {
			if PriorityQueue_Peek(ctx, q) != Some(value) || PriorityQueue_Dequeue(ctx, q) != Some(value) {
				t.Fatalf("size=%d item=%d, want %+v", size, i, value)
			}
		}
		if PriorityQueue_Dequeue(ctx, q).Some {
			t.Fatalf("size=%d not empty after drain", size)
		}
	}
}

func TestPriorityQueueDequeueFaultLeavesHeapIntact(t *testing.T) {
	ctx := RootExecution()
	// Count a successful descent, then fault at each of its comparisons.
	// This includes faults after part of the path has already been prepared.
	count, failAt := 0, 0
	compare := func(_ *Execution, a, b int) int {
		count++
		if failAt == count {
			Raise("dequeue comparator")
		}
		if a < b {
			return -1
		}
		if a > b {
			return 1
		}
		return 0
	}
	makeQueue := func() *PriorityQueue[int] {
		q := NewPriorityQueue(compare, None[int]())
		for i := 0; i < 1024; i++ {
			PriorityQueue_Enqueue(ctx, q, i)
		}
		count = 0
		return q
	}
	q := makeQueue()
	PriorityQueue_Dequeue(ctx, q)
	comparisons := count
	if comparisons < 10 {
		t.Fatalf("descent too short: %d comparisons", comparisons)
	}
	for stop := 1; stop <= comparisons; stop++ {
		q = makeQueue()
		before := append([]priorityEntry[int](nil), q.items...)
		next := q.next
		failAt = stop
		mustFault(t, "dequeue comparator", func() { PriorityQueue_Dequeue(ctx, q) })
		failAt = 0
		if !reflect.DeepEqual(q.items, before) || q.next != next {
			t.Fatalf("comparison %d changed the queue", stop)
		}
		for want := 0; want < len(before); want++ {
			if got := PriorityQueue_Dequeue(ctx, q); got != Some(want) {
				t.Fatalf("after fault %d, dequeue = %v, want %d", stop, got, want)
			}
		}
	}
}

func TestPriorityQueueDequeueReleasesRemovedPayloads(t *testing.T) {
	ctx := RootExecution()
	q := NewPriorityQueue(func(_ *Execution, a, b *int) int { return *a - *b }, None[int]())
	for _, n := range []int{0, 2, 1} {
		v := n
		PriorityQueue_Enqueue(ctx, q, &v)
	}
	storage := q.items
	for want := 0; want < 3; want++ {
		got := PriorityQueue_Dequeue(ctx, q)
		if !got.Some || *got.Val != want {
			t.Fatalf("dequeue = %v, want %d", got, want)
		}
		if storage[2-want] != (priorityEntry[*int]{}) {
			t.Fatal("removed tail retains payload")
		}
	}
	if q.items != nil || q.next != 0 || PriorityQueue_Dequeue(ctx, q).Some {
		t.Fatal("empty state")
	}
}

func TestPriorityQueueDequeueCancellationLeavesHeapIntact(t *testing.T) {
	ctx, cancel := cancelledExecution()
	defer cancel()
	armed, calls := false, 0
	q := NewPriorityQueue(func(c *Execution, a, b int) int {
		if armed {
			calls++
			if calls == 5 {
				cancel()
			}
			CheckCancelled(c)
		}
		return a - b
	}, None[int]())
	for i := 0; i < 1024; i++ {
		PriorityQueue_Enqueue(ctx, q, i)
	}
	before := append([]priorityEntry[int](nil), q.items...)
	armed = true
	func() {
		defer func() {
			if _, ok := recover().(cancelled); !ok {
				t.Fatal("expected callback cancellation")
			}
		}()
		PriorityQueue_Dequeue(ctx, q)
	}()
	if !reflect.DeepEqual(q.items, before) || q.next != 1024 {
		t.Fatal("cancellation changed the queue")
	}
}
