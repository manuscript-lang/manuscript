package msruntime

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

func mustFault(t *testing.T, contains string, f func()) {
	t.Helper()
	defer func() {
		r := recover()
		fault, ok := r.(Fault)
		if !ok {
			t.Fatalf("expected a fault containing %q, got %v", contains, r)
		}
		if !strings.Contains(fault.Message, contains) {
			t.Fatalf("fault %q does not contain %q", fault.Message, contains)
		}
	}()
	f()
}

func cancelledExecution() (*Execution, context.CancelFunc) {
	ctx, cancel := context.WithCancel(context.Background())
	return rootExecution(ctx, nil), cancel
}

func TestQueue(t *testing.T) {
	ctx := RootExecution()
	q := NewQueue[int](Some(int(2)))
	if !Queue_Enqueue(ctx, q, 1) || !Queue_Enqueue(ctx, q, 2) || Queue_Enqueue(ctx, q, 3) {
		t.Fatal("capacity")
	}
	if p := Queue_Peek(ctx, q); !p.Some || p.Val != 1 || Queue_Length(ctx, q) != 2 || Queue_IsEmpty(ctx, q) {
		t.Fatal("peek")
	}
	if d := Queue_Dequeue(ctx, q); d.Val != 1 || !d.Some {
		t.Fatal("dequeue")
	}
	Queue_Dequeue(ctx, q)
	if Queue_Dequeue(ctx, q).Some || !Queue_IsEmpty(ctx, q) {
		t.Fatal("empty")
	}
	mustFault(t, "Queue: capacity must be between 1", func() { NewQueue[int](Some(int(0))) })
	unbounded := NewQueue[int](None[int]())
	for i := int(0); i < 1000; i++ {
		Queue_Enqueue(ctx, unbounded, i)
	}
	if Queue_Length(ctx, unbounded) != 1000 {
		t.Fatal("unbounded")
	}
}

func TestPriorityQueueOrderAndStability(t *testing.T) {
	ctx := RootExecution()
	type item struct{ priority, id int }
	q := NewPriorityQueue(func(_ *Execution, a, b item) int { return a.priority - b.priority }, None[int]())
	for i, p := range []int{3, 1, 2, 1, 3, 1} {
		PriorityQueue_Enqueue(ctx, q, item{p, int(i)})
	}
	var got []string
	for !PriorityQueue_IsEmpty(ctx, q) {
		peek := PriorityQueue_Peek(ctx, q)
		v := PriorityQueue_Dequeue(ctx, q)
		if peek.Val != v.Val {
			t.Fatal("peek differs from dequeue")
		}
		got = append(got, fmt.Sprint(v.Val.priority, ":", v.Val.id))
	}
	if want := "1:1 1:3 1:5 2:2 3:0 3:4"; strings.Join(got, " ") != want {
		t.Fatalf("got %v", got)
	}
}

func TestPriorityQueueComparatorFaultLeavesHeapIntact(t *testing.T) {
	ctx := RootExecution()
	fail := false
	q := NewPriorityQueue(func(_ *Execution, a, b int) int {
		if fail {
			Raise("cmp")
		}
		return a - b
	}, Some(int(3)))
	PriorityQueue_Enqueue(ctx, q, 2)
	PriorityQueue_Enqueue(ctx, q, 1)
	fail = true
	mustFault(t, "cmp", func() { PriorityQueue_Enqueue(ctx, q, 0) })
	fail = false
	if PriorityQueue_Length(ctx, q) != 2 || PriorityQueue_Dequeue(ctx, q).Val != 1 {
		t.Fatal("heap changed by failed enqueue")
	}
	PriorityQueue_Enqueue(ctx, q, 5)
	PriorityQueue_Enqueue(ctx, q, 6)
	if PriorityQueue_Enqueue(ctx, q, 7) {
		t.Fatal("capacity")
	}
}

func TestCheckCancelled(t *testing.T) {
	CheckCancelled(RootExecution())
	cancelledCtx, cancel := cancelledExecution()
	cancel()
	func() {
		defer func() {
			if _, ok := recover().(cancelled); !ok {
				t.Fatal("no cancellation")
			}
		}()
		CheckCancelled(cancelledCtx)
	}()
	// Shield ignores cancellation.
	CheckCancelled(Shield(cancelledCtx))
}
