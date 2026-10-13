package msruntime

import (
	"sync"
	"testing"
)

func TestQueueWithoutCapacityGrowsAndReuses(t *testing.T) {
	ctx := RootExecution()
	q := ConstructWithContext(ctx, "@std/Queue[Int]", nil).(*Queue)
	for range 2 {
		for i := range 4096 {
			if Invoke(ctx, q.Operation("enqueue"), []Argument{{"value", int32(i)}}) != true {
				t.Fatal("unbounded queue rejected an item", i)
			}
		}
		if Invoke(ctx, q.Operation("length"), nil) != int32(4096) {
			t.Fatal("unbounded queue lost items")
		}
		for i := range 4096 {
			value := Invoke(ctx, q.Operation("dequeue"), nil).(Alternative)
			if value.Tag != "some" || value.Fields[0] != int32(i) {
				t.Fatal("unbounded queue lost FIFO order", i, value)
			}
		}
		if Invoke(ctx, q.Operation("dequeue"), nil).(Alternative).Tag != "none" {
			t.Fatal("unbounded queue did not drain")
		}
	}
}

func TestQueueFIFOEmptyAndReuse(t *testing.T) {
	ctx := RootExecution()
	q := ConstructWithContext(ctx, "@std/Queue[Int]", []Argument{{"capacity", int32(100)}}).(*Queue)
	for range 2 {
		if Invoke(ctx, q.Operation("dequeue"), nil).(Alternative).Tag != "none" || Invoke(ctx, q.Operation("peek"), nil).(Alternative).Tag != "none" {
			t.Fatal("empty queue must return none immediately")
		}
	}
	enqueue := q.Operation("enqueue")
	dequeue := q.Operation("dequeue")
	for round := range 3 {
		for i := range 100 {
			if Invoke(ctx, enqueue, []Argument{{"value", int32(round*100 + i)}}) != true {
				t.Fatal("enqueue failed before capacity")
			}
		}
		if Invoke(ctx, enqueue, []Argument{{"value", int32(-1)}}) != false {
			t.Fatal("full queue must reject without waiting")
		}
		for i := range 100 {
			if Invoke(ctx, q.Operation("length"), nil) != int32(100-i) || Invoke(ctx, q.Operation("is_empty"), nil) != false {
				t.Fatal("incorrect queue size")
			}
			peek := Invoke(ctx, q.Operation("peek"), nil).(Alternative)
			storage := q.items
			value := Invoke(ctx, dequeue, nil).(Alternative)
			if value.Tag != "some" || value.Fields[0] != int32(round*100+i) || !Equal(peek, value) {
				t.Fatal("queue lost FIFO order", peek, value)
			}
			if storage[0] != nil {
				t.Fatal("dequeued slot retained its value")
			}
		}
		if Invoke(ctx, q.Operation("is_empty"), nil) != true || q.items != nil {
			t.Fatal("drained queue retained storage")
		}
	}
}

func TestQueueSharedThroughSynchronized(t *testing.T) {
	root := RootExecution()
	q := ConstructWithContext(root, "@std/Queue[Int]", []Argument{{"capacity", int32(1600)}})
	cell := ConstructWithContext(root, "@std/Synchronized[@std/Queue[Int]]", []Argument{{"value", q}}).(*Synchronized)
	const workers, count = 16, 100
	var wait sync.WaitGroup
	for worker := range workers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			ctx := newExecution(root, root.Context)
			for i := range count {
				guard := lockCell(ctx, cell)
				queue := Invoke(ctx, guard.Operation("get"), nil).(*Queue)
				Invoke(ctx, queue.Operation("enqueue"), []Argument{{"value", int32(worker*count + i)}})
				guard.close()
			}
		}()
	}
	wait.Wait()
	guard := lockCell(root, cell)
	defer guard.close()
	queue := Invoke(root, guard.Operation("get"), nil).(*Queue)
	if Invoke(root, queue.Operation("length"), nil) != int32(workers*count) {
		t.Fatal("lost concurrent enqueue")
	}
	seen := make(map[int32]bool)
	last := make([]int32, workers)
	for i := range last {
		last[i] = -1
	}
	for range workers * count {
		item := Invoke(root, queue.Operation("dequeue"), nil).(Alternative)
		value := item.Fields[0].(int32)
		worker, sequence := value/count, value%count
		if seen[value] || sequence != last[worker]+1 {
			t.Fatal("duplicated value or lost producer order", value)
		}
		seen[value] = true
		last[worker] = sequence
	}
	if Invoke(root, queue.Operation("dequeue"), nil).(Alternative).Tag != "none" {
		t.Fatal("queue did not drain")
	}
}

func TestQueueRejectsInvalidCapacity(t *testing.T) {
	for _, capacity := range []int32{0, -1} {
		failure := recovered(func() { ConstructWithContext(RootExecution(), "@std/Queue[Int]", []Argument{{"capacity", capacity}}) })
		if _, ok := failure.(Fault); !ok {
			t.Fatal("invalid capacity accepted", capacity, failure)
		}
	}
}
