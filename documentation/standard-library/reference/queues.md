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

## Queue {data-api-kind="Native type"}

FIFO queue. An omitted capacity creates an unbounded queue.

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

Optional constructor argument; omit for an unbounded queue.

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

### Queue.peek

Returns the oldest value without removing it.

```manuscript
fn peek() -> Optional[T]:
```

