package rt

import "sync"

func queueCapacity(name string, capacity Option[int64]) int {
	if !capacity.Some {
		return 0
	}
	if capacity.Val <= 0 || capacity.Val > int64(^uint(0)>>1) {
		rangeFault(name, "capacity", 1, capacity.Val)
	}
	return int(capacity.Val)
}

// Queue is a local mutable FIFO. Concurrent callers must protect every access
// with the same Synchronized acquisition, including reads and saved methods;
// the old runtime's implicit per-value locking is gone.
type Queue[T any] struct {
	capacity int // zero means unbounded
	items    []T
}

// NewQueue constructs a Queue with an optional positive capacity.
func NewQueue[T any](capacity Option[int64]) *Queue[T] {
	return &Queue[T]{capacity: queueCapacity("Queue", capacity)}
}

// Queue_Enqueue appends a value, returning false when a bounded queue is full.
func Queue_Enqueue[T any](_ *Execution, q *Queue[T], value T) bool {
	if q.capacity > 0 && len(q.items) == q.capacity {
		return false
	}
	q.items = append(q.items, value)
	return true
}

// Queue_Dequeue removes and returns the oldest value.
func Queue_Dequeue[T any](_ *Execution, q *Queue[T]) Option[T] {
	if len(q.items) == 0 {
		return None[T]()
	}
	value := q.items[0]
	q.items[0] = Zero[T]()
	q.items = q.items[1:]
	if len(q.items) == 0 {
		q.items = nil
	}
	return Some(value)
}

// Queue_Peek returns the oldest value without removing it.
func Queue_Peek[T any](_ *Execution, q *Queue[T]) Option[T] {
	if len(q.items) == 0 {
		return None[T]()
	}
	return Some(q.items[0])
}

// Queue_Length is the number of waiting values.
func Queue_Length[T any](_ *Execution, q *Queue[T]) int64 { return int64(len(q.items)) }

// Queue_IsEmpty reports whether dequeue and peek would return none.
func Queue_IsEmpty[T any](_ *Execution, q *Queue[T]) bool { return len(q.items) == 0 }

// BlockingQueue is a FIFO whose put and take wait for free space or a value.
// It synchronizes its own state, so callers share it without Synchronized.
// A waiting operation holds no lock and stops at cancellation.
type BlockingQueue[T any] struct {
	mu       sync.Mutex
	capacity int // zero means unbounded
	items    []T
	closed   bool
	changed  chan struct{}
}

// NewBlockingQueue constructs a BlockingQueue with an optional positive capacity.
func NewBlockingQueue[T any](capacity Option[int64]) *BlockingQueue[T] {
	return &BlockingQueue[T]{capacity: queueCapacity("BlockingQueue", capacity), changed: make(chan struct{})}
}

// signal wakes every waiter. The caller holds q.mu.
func (q *BlockingQueue[T]) signal() {
	close(q.changed)
	q.changed = make(chan struct{})
}

// await releases q.mu, waits for a change or cancellation, and relocks.
func (q *BlockingQueue[T]) await(ctx *Execution) {
	changed := q.changed
	q.mu.Unlock()
	select {
	case <-changed:
	case <-ctx.Context.Done():
	}
	q.mu.Lock()
	// A cancellation fault unwinds through the caller's deferred unlock.
	CheckCancelled(ctx)
}

// BlockingQueue_Put waits for free space, appends, and returns true; false
// once the queue is closed.
func BlockingQueue_Put[T any](ctx *Execution, q *BlockingQueue[T], value T) bool {
	CheckCancelled(ctx)
	q.mu.Lock()
	defer q.mu.Unlock()
	for {
		if q.closed {
			return false
		}
		if q.capacity == 0 || len(q.items) < q.capacity {
			q.items = append(q.items, value)
			q.signal()
			return true
		}
		q.await(ctx)
	}
}

// BlockingQueue_Take waits for a value and removes the oldest; none once the
// queue is closed and empty.
func BlockingQueue_Take[T any](ctx *Execution, q *BlockingQueue[T]) Option[T] {
	CheckCancelled(ctx)
	q.mu.Lock()
	defer q.mu.Unlock()
	for {
		if len(q.items) > 0 {
			value := q.items[0]
			q.items[0] = Zero[T]()
			q.items = q.items[1:]
			if len(q.items) == 0 {
				q.items = nil
			}
			q.signal()
			return Some(value)
		}
		if q.closed {
			return None[T]()
		}
		q.await(ctx)
	}
}

// BlockingQueue_Close stops new puts and wakes every waiting task.
func BlockingQueue_Close[T any](_ *Execution, q *BlockingQueue[T]) Unit {
	q.mu.Lock()
	defer q.mu.Unlock()
	if !q.closed {
		q.closed = true
		q.signal()
	}
	return Unit{}
}

// BlockingQueue_Length is the number of waiting values.
func BlockingQueue_Length[T any](_ *Execution, q *BlockingQueue[T]) int64 {
	q.mu.Lock()
	defer q.mu.Unlock()
	return int64(len(q.items))
}

// BlockingQueue_IsClosed reports whether close has been called.
func BlockingQueue_IsClosed[T any](_ *Execution, q *BlockingQueue[T]) bool {
	q.mu.Lock()
	defer q.mu.Unlock()
	return q.closed
}

type priorityEntry[T any] struct {
	value    T
	sequence uint64
}

// PriorityQueue is a local stable binary heap. Shared access uses
// Synchronized. Comparators must be consistent and must not mutate this queue.
type PriorityQueue[T any] struct {
	compare  func(*Execution, T, T) int64
	capacity int
	next     uint64
	items    []priorityEntry[T]
}

// NewPriorityQueue constructs a PriorityQueue from its comparator and optional
// positive capacity.
func NewPriorityQueue[T any](compare func(*Execution, T, T) int64, capacity Option[int64]) *PriorityQueue[T] {
	return &PriorityQueue[T]{compare: compare, capacity: queueCapacity("PriorityQueue", capacity)}
}

func (q *PriorityQueue[T]) before(ctx *Execution, left, right priorityEntry[T]) bool {
	order := q.compare(ctx, left.value, right.value)
	return order < 0 || order == 0 && left.sequence < right.sequence
}

// PriorityQueue_Enqueue adds a value, returning false when the queue is full.
func PriorityQueue_Enqueue[T any](ctx *Execution, q *PriorityQueue[T], value T) bool {
	if q.capacity > 0 && len(q.items) >= q.capacity {
		return false
	}
	entry := priorityEntry[T]{value, q.next}
	at := len(q.items)
	for at > 0 {
		parent := (at - 1) / 2
		if !q.before(ctx, entry, q.items[parent]) {
			break
		}
		at = parent
	}
	// Compare before mutating, so a comparator fault leaves the heap intact.
	q.items = append(q.items, entry)
	for i := len(q.items) - 1; i > at; {
		parent := (i - 1) / 2
		q.items[i] = q.items[parent]
		i = parent
	}
	q.items[at] = entry
	q.next++
	return true
}

// PriorityQueue_Dequeue removes and returns the next value by priority.
func PriorityQueue_Dequeue[T any](ctx *Execution, q *PriorityQueue[T]) Option[T] {
	if len(q.items) == 0 {
		return None[T]()
	}
	value := q.items[0].value
	last := len(q.items) - 1
	entry := q.items[last]
	var path []int
	at := 0
	for {
		child := at*2 + 1
		if child >= last {
			break
		}
		if child+1 < last && q.before(ctx, q.items[child+1], q.items[child]) {
			child++
		}
		if !q.before(ctx, q.items[child], entry) {
			break
		}
		path = append(path, child)
		at = child
	}
	at = 0
	for _, child := range path {
		q.items[at] = q.items[child]
		at = child
	}
	if last > 0 {
		q.items[at] = entry
	}
	q.items[last] = priorityEntry[T]{}
	q.items = q.items[:last]
	if last == 0 {
		q.items = nil
		q.next = 0
	}
	return Some(value)
}

// PriorityQueue_Peek returns the next value by priority without removing it.
func PriorityQueue_Peek[T any](_ *Execution, q *PriorityQueue[T]) Option[T] {
	if len(q.items) == 0 {
		return None[T]()
	}
	return Some(q.items[0].value)
}

// PriorityQueue_Length is the number of enqueued values.
func PriorityQueue_Length[T any](_ *Execution, q *PriorityQueue[T]) int64 {
	return int64(len(q.items))
}

// PriorityQueue_IsEmpty reports whether the queue holds no values.
func PriorityQueue_IsEmpty[T any](_ *Execution, q *PriorityQueue[T]) bool {
	return len(q.items) == 0
}
