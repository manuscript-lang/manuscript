package msruntime

func queueCapacity(name string, capacity Option[int]) int {
	if !capacity.Some {
		return 0
	}
	if capacity.Val <= 0 || capacity.Val > int(^uint(0)>>1) {
		minRangeFault(name, "capacity", 1, capacity.Val)
	}
	return int(capacity.Val)
}

// Queue is a local mutable FIFO.
type Queue[T any] struct {
	capacity int // zero means unbounded
	items    []T
}

// NewQueue constructs a Queue with an optional positive capacity.
func NewQueue[T any](capacity Option[int]) *Queue[T] {
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
func Queue_Length[T any](_ *Execution, q *Queue[T]) int { return len(q.items) }

// Queue_IsEmpty reports whether dequeue and peek would return none.
func Queue_IsEmpty[T any](_ *Execution, q *Queue[T]) bool { return len(q.items) == 0 }

type priorityEntry[T any] struct {
	value    T
	sequence uint64
}

// PriorityQueue is a local stable binary heap. Comparators must be consistent
// and must not mutate this queue.
type PriorityQueue[T any] struct {
	compare  func(*Execution, T, T) int
	capacity int
	next     uint64
	items    []priorityEntry[T]
}

// NewPriorityQueue constructs a PriorityQueue from its comparator and optional
// positive capacity.
func NewPriorityQueue[T any](compare func(*Execution, T, T) int, capacity Option[int]) *PriorityQueue[T] {
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
	depth := 0
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
		depth++
		at = child
	}
	// The binary digits of a heap index + 1, after the leading 1, encode
	// its left/right path. Replay it only after every comparison succeeds,
	// keeping comparator faults atomic without allocating a path slice.
	path := at + 1
	at = 0
	for level := depth - 1; level >= 0; level-- {
		child := at*2 + 1 + ((path >> level) & 1)
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
func PriorityQueue_Length[T any](_ *Execution, q *PriorityQueue[T]) int {
	return len(q.items)
}

// PriorityQueue_IsEmpty reports whether the queue holds no values.
func PriorityQueue_IsEmpty[T any](_ *Execution, q *PriorityQueue[T]) bool {
	return len(q.items) == 0
}
