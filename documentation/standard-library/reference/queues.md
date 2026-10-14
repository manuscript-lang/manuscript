+++
title = "queues"
+++

# @std/queues.ms

Import each required symbol with `import Name from "@std/queues.ms"`.

## PriorityQueue {data-api-kind="Native type"}

Negative compare results put left before right; equal priorities remain FIFO.

```manuscript
type PriorityQueue[T]:
    compare: fn(left: T, right: T) -> Int
    capacity: Optional[Int] = none
    fn enqueue(value: T) -> Bool:
    fn dequeue() -> Optional[T]:
    fn peek() -> Optional[T]:
    fn length() -> Int:
    fn is_empty() -> Bool:
```

### PriorityQueue.capacity

Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.

```manuscript
capacity: Optional[Int] = none
```

### PriorityQueue.compare

Constructor comparator: negative puts left first; ties dequeue in enqueue order.
Comparisons must stay consistent and must not mutate this queue.

```manuscript
compare: fn(left: T, right: T) -> Int
```

### PriorityQueue.dequeue

Removes and returns the next value by priority, or `none` when empty.

```manuscript
fn dequeue() -> Optional[T]:
```

### PriorityQueue.enqueue

Adds a value, returning false when a bounded queue is full.

```manuscript
fn enqueue(value: T) -> Bool:
```

### PriorityQueue.is_empty

Reports whether the queue has no values to peek or dequeue.

```manuscript
fn is_empty() -> Bool:
```

### PriorityQueue.length

Returns the number of enqueued values, independent of their priorities.

```manuscript
fn length() -> Int:
```

### PriorityQueue.peek

Returns the next value by priority without removing it, or none when empty.

```manuscript
fn peek() -> Optional[T]:
```

## Queue {data-api-kind="Native type"}

A local mutable FIFO queue; protect all shared access with Synchronized.
Omitted or none capacity grows as needed and adds no fixed queue limit.

```manuscript
type Queue[T]:
    capacity: Optional[Int] = none
    fn enqueue(value: T) -> Bool:
    fn dequeue() -> Optional[T]:
    fn peek() -> Optional[T]:
    fn length() -> Int:
    fn is_empty() -> Bool:
```

### Queue.capacity

Constructor capacity in items; omission/none is unbounded, and supplied values must be positive.

```manuscript
capacity: Optional[Int] = none
```

### Queue.dequeue

Removes and returns the oldest value, or `none` when empty.

```manuscript
fn dequeue() -> Optional[T]:
```

### Queue.enqueue

Adds a value, returning false when a bounded queue is full.

```manuscript
fn enqueue(value: T) -> Bool:
```

### Queue.is_empty

Reports whether dequeue and peek would return none.

```manuscript
fn is_empty() -> Bool:
```

### Queue.length

Returns the number of values currently waiting in the queue.

```manuscript
fn length() -> Int:
```

### Queue.peek

Returns the oldest value without removing it, or none when the queue is empty.

```manuscript
fn peek() -> Optional[T]:
```

