package msruntime

import (
	"context"
	"testing"
	"time"
)

func blockingInt(capacity int) *BlockingQueue {
	return newBlockingQueue("@std/BlockingQueue[Int]", capacity)
}

func queueOp(ctx *Execution, q *BlockingQueue, name string, args ...Argument) Value {
	return Invoke(ctx, q.Operation(name), args)
}

func TestBlockingQueueTakeWaitsForPut(t *testing.T) {
	root := RootExecution()
	q := blockingInt(0)
	got := make(chan Value, 1)
	go func() { got <- queueOp(newExecution(root, root.Context), q, "take") }()
	select {
	case <-got:
		t.Fatal("take returned on an empty queue")
	case <-time.After(20 * time.Millisecond):
	}
	if queueOp(root, q, "put", Argument{"value", int64(5)}) != true {
		t.Fatal("put refused")
	}
	select {
	case value := <-got:
		if value.(Alternative).Tag != "some" {
			t.Fatalf("take returned %v", value)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("take did not wake")
	}
}

func TestBlockingQueuePutWaitsForSpaceAndKeepsOrder(t *testing.T) {
	root := RootExecution()
	q := blockingInt(1)
	queueOp(root, q, "put", Argument{"value", int64(1)})
	done := make(chan Value, 1)
	go func() { done <- queueOp(newExecution(root, root.Context), q, "put", Argument{"value", int64(2)}) }()
	select {
	case <-done:
		t.Fatal("put returned on a full queue")
	case <-time.After(20 * time.Millisecond):
	}
	first := queueOp(root, q, "take").(Alternative)
	if first.Tag != "some" || first.Fields[0] != int64(1) {
		t.Fatalf("first take: %v", first)
	}
	if v := <-done; v != true {
		t.Fatalf("blocked put result: %v", v)
	}
	if second := queueOp(root, q, "take").(Alternative); second.Fields[0] != int64(2) {
		t.Fatalf("second take: %v", second)
	}
}

func TestBlockingQueueCloseWakesWaitersAndDrains(t *testing.T) {
	root := RootExecution()
	q := blockingInt(0)
	results := make(chan Value, 2)
	for range 2 {
		go func() { results <- queueOp(newExecution(root, root.Context), q, "take") }()
	}
	time.Sleep(20 * time.Millisecond)
	queueOp(root, q, "close")
	queueOp(root, q, "close")
	for range 2 {
		select {
		case v := <-results:
			if v.(Alternative).Tag != "none" {
				t.Fatalf("closed empty take: %v", v)
			}
		case <-time.After(2 * time.Second):
			t.Fatal("close did not wake takers")
		}
	}
	if queueOp(root, q, "put", Argument{"value", int64(1)}) != false {
		t.Fatal("put after close succeeded")
	}
}

func TestBlockingQueueCancellationUnblocksWaiters(t *testing.T) {
	root := RootExecution()
	for _, name := range []string{"take", "put"} {
		q := blockingInt(1)
		queueOp(root, q, "put", Argument{"value", int64(1)})
		if name == "take" {
			queueOp(root, q, "take")
		}
		ctx, cancel := context.WithCancel(root.Context)
		waiter := newExecution(root, ctx)
		done := make(chan any, 1)
		go func() {
			done <- recovered(func() {
				if name == "put" {
					queueOp(waiter, q, "put", Argument{"value", int64(2)})
					return
				}
				queueOp(waiter, q, "take")
			})
		}()
		time.Sleep(20 * time.Millisecond)
		cancel()
		select {
		case failure := <-done:
			if _, ok := failure.(cancelled); !ok {
				t.Fatalf("%s: %v", name, failure)
			}
		case <-time.After(2 * time.Second):
			t.Fatalf("%s did not stop at cancellation", name)
		}
		// The queue stays usable after a cancelled waiter.
		queueOp(root, q, "close")
	}
}
