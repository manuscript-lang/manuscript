+++
title = "Local queues"
weight = 41
+++

# Local queues

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

`Queue[T]` is a mutable FIFO for single-threaded use. Import it from `@std/queues.ms`. Omit capacity for an unbounded queue, or supply a positive capacity to bound it. Every operation returns immediately: enqueue returns `false` when full, and dequeue returns `none` when empty.

```manuscript
import Queue from "@std/queues.ms"
import panic from "@std/faults.ms"

test "a local queue":
    let queue = Queue[Int]()
    queue.enqueue(10)
    match queue.dequeue():
        some(value):
            if value != 10:
                return panic("unexpected value")
        none:
            return panic("queue is empty")
```

## API

`Queue[T]()` creates an empty, unbounded queue. `Queue[T](capacity: Int)` creates an empty queue with a fixed positive capacity. A nonpositive capacity is a programming fault. Elements may be any value type, including functions and contract views. The queue is an opaque reference without equality or hashing; aliases and saved methods use the same queue.

```manuscript
fn enqueue(value: T) -> Bool
fn dequeue() -> Optional[T]
fn peek() -> Optional[T]
fn length() -> Int
fn is_empty() -> Bool
```

`enqueue` appends at the back and returns `true`, or leaves a bounded queue unchanged and returns `false` when full. An unbounded queue grows as needed and always accepts an enqueue. `dequeue` removes the oldest value; `peek` reads it without removal. Both return `none` when empty. Dequeuing frees capacity, and an empty queue may be reused. There is no waiting, close operation, cleanup registration, or end-of-stream state. A queue cannot be a `with` initializer.

## Sharing a queue

For concurrent access, put the queue in one `Synchronized[Queue[T]]` and hold its guard throughout every operation, including reads. Each caller acquires its own guard from the same wrapper:

```manuscript
import Queue from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import Optional from "@std/optional.ms"

fn make_queue() -> Synchronized[Queue[Int]]:
    return Synchronized(value: Queue[Int](capacity: 16))

fn enqueue(shared: Synchronized[Queue[Int]], value: Int) -> Bool:
    with locked = shared.lock():
        return locked.get().enqueue(value)

fn dequeue(shared: Synchronized[Queue[Int]]) -> Optional[Int]:
    with locked = shared.lock():
        return locked.get().dequeue()
```

The queue itself has no mutex. The compiler allows references to be passed freely and does not enforce this locking discipline. A queue or bound method obtained through `locked.get()` remains an alias after the guard closes; it must not be used concurrently outside that lock. Wrapping the same queue in two separate synchronized containers does not coordinate them. Store the queue directly in one wrapper and share that wrapper.

Wrapping a queue serializes access; it does not add waiting for values or free capacity. Never wait for another operation to fill or drain the queue while holding its lock. Lock acquisition follows the ordinary [Synchronized cancellation and cleanup rules](synchronized-state.md#synchronized).

[Previous: Readers, writers, and streams](streams.md) · [Next: Synchronized values, pools, and leases](synchronized-state.md)
