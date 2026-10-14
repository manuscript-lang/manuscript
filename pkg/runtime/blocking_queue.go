package msruntime

import "sync"

// BlockingQueue is a FIFO whose put and take wait for free space or a value.
// It synchronizes its own state, so callers share it without Synchronized.
// A waiting operation holds no lock and stops at cancellation.
type BlockingQueue struct {
	mu       sync.Mutex
	typ      string
	capacity int // Zero means unbounded; explicitly supplied capacities must be positive.
	items    []Value
	closed   bool
	changed  chan struct{}
}

func newBlockingQueue(typ string, capacity int) *BlockingQueue {
	return &BlockingQueue{typ: typ, capacity: capacity, changed: make(chan struct{})}
}

// signal wakes every waiter. The caller holds q.mu.
func (q *BlockingQueue) signal() {
	close(q.changed)
	q.changed = make(chan struct{})
}

// await releases q.mu, waits for a change or cancellation, and relocks.
func (q *BlockingQueue) await(ctx *Execution) {
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

func (q *BlockingQueue) put(ctx *Execution, value Value) bool {
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

func (q *BlockingQueue) take(ctx *Execution, element string) Value {
	CheckCancelled(ctx)
	q.mu.Lock()
	defer q.mu.Unlock()
	for {
		if len(q.items) > 0 {
			value := q.items[0]
			q.items[0] = nil
			q.items = q.items[1:]
			if len(q.items) == 0 {
				q.items = nil
			}
			q.signal()
			return optional(element, value, true)
		}
		if q.closed {
			return optional(element, nil, false)
		}
		q.await(ctx)
	}
}

func (q *BlockingQueue) Operation(name string) Function {
	element := typeArguments(q.typ)[0]
	labels, result := []string{}, "Unit"
	switch name {
	case "put":
		labels, result = []string{"value"}, "Bool"
	case "take":
		result = "@std/Optional[" + element + "]"
	case "length":
		result = "Int"
	case "is_closed":
		result = "Bool"
	case "close":
	default:
		Panic("unknown BlockingQueue operation")
	}
	return NewFunction(labels, result, func(ctx *Execution, args []Value) Value {
		switch name {
		case "put":
			return q.put(ctx, args[0])
		case "take":
			return q.take(ctx, element)
		}
		q.mu.Lock()
		defer q.mu.Unlock()
		switch name {
		case "length":
			return int64(len(q.items))
		case "is_closed":
			return q.closed
		}
		if !q.closed {
			q.closed = true
			q.signal()
		}
		return Unit{}
	})
}
