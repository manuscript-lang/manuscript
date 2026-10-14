+++
title = "Queues"
weight = 7
+++

# Queues

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

fn make_queue() -> Synchronized[Queue[Int]]:
    return Synchronized(Queue[Int](16))

fn enqueue(shared: Synchronized[Queue[Int]], value: Int) -> Bool:
    with locked = shared.lock():
        return locked.get().enqueue(value)

fn dequeue(shared: Synchronized[Queue[Int]]) -> Optional[Int]:
    with locked = shared.lock():
        return locked.get().dequeue()
```

The queue itself has no mutex. The compiler allows references to be passed freely and does not enforce this locking discipline. A queue or bound method obtained through `locked.get()` remains an alias after the guard closes; it must not be used concurrently outside that lock. Wrapping the same queue in two separate synchronized containers does not coordinate them. Store the queue directly in one wrapper and share that wrapper.

Wrapping a queue serializes access; it does not by itself add waiting for values or free capacity. To block until the queue changes, call the guard's [`wait()`](synchronization.md#waiting-for-a-change), which releases the lock while sleeping; never poll or spin while holding the lock. Lock acquisition follows the ordinary [Synchronized cancellation and cleanup rules](synchronization.md#synchronized).

## Blocking queue

Waiting for values or free capacity composes from `Synchronized` and `wait`/`notify_all`. `BlockingQueue` below is ordinary Manuscript, not a standard type. The doc comment on the type shows how to use it; the test bounds the queue at two items, and the consumer runs in a `TaskGroup` so it cannot outlive its scope:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import Queue from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import TaskGroup from "@std/tasks.ms"
import panic from "@std/faults.ms"

type QueueState[T]:
    items: Queue[T]
    closed: Bool

# A bounded FIFO queue that blocks producers while it is full and consumers while it is empty.
#
# Create one with new_blocking_queue(capacity) and share it between tasks started by a TaskGroup.
# put(queue, value) waits for free space and returns false once the queue is closed.
# take(queue) waits for a value and returns none once the queue is closed and drained.
# close_queue(queue) stops new puts and wakes every waiting task.
#
# Example: a producer feeds two workers.
#
#     let queue = new_blocking_queue[Int](8)
#     with group = TaskGroup():
#         group.start(fn(): work(queue: queue))
#         group.start(fn(): work(queue: queue))
#         put(queue: queue, value: 1)
#         close_queue(queue: queue)
#
# Leaving the TaskGroup scope early cancels workers blocked in take; they unwind without the lock.
type BlockingQueue[T]:
    state: Synchronized[QueueState[T]]

# Creates an empty queue holding at most capacity values.
fn new_blocking_queue[T](capacity: Int) -> BlockingQueue[T]:
    let state = QueueState(items: Queue[T](capacity), closed: false)
    return BlockingQueue(state: Synchronized(state))

# Waits for free space, then adds value. Returns false if the queue is closed.
fn put[T](queue: BlockingQueue[T], value: T) -> Bool:
    with locked = queue.state.lock():
        while true:
            let current = locked.get()
            if current.closed:
                return false
            if current.items.enqueue(value):
                locked.notify_all()
                return true
            locked.wait()
    return false

# Waits for a value and removes the oldest one. Returns none once the queue is closed and empty.
fn take[T](queue: BlockingQueue[T]) -> Optional[T]:
    with locked = queue.state.lock():
        while true:
            let current = locked.get()
            let item = current.items.dequeue()
            if item.is_some():
                locked.notify_all()
                return item
            if current.closed:
                return none
            locked.wait()
    return none

# Stops new puts and wakes every waiting task. Queued values can still be taken.
fn close_queue[T](queue: BlockingQueue[T]) -> Unit:
    with locked = queue.state.lock():
        let current = locked.get()
        current.closed = true
        locked.notify_all()

fn work(queue: BlockingQueue[Int]) -> Int:
    var total = 0
    while true:
        match take(queue: queue):
            some(value):
                total = total + value
            none:
                return total
    return total

test "a producer feeds a consumer through a bounded queue":
    let queue = new_blocking_queue[Int](2)
    with group = TaskGroup():
        let consumer = group.start(fn(): work(queue: queue))
        for value in [1, 2, 3, 4, 5]:
            if not put(queue: queue, value: value):
                return panic(message: "put failed")
        close_queue(queue: queue)
        match consumer.join():
            ok(total):
                if not (total == 15):
                    return panic(message: "lost or duplicated items")
            error(_):
                return panic(message: "consumer failed")
```

`put` blocks while the queue is full and `take` blocks while it is empty. After `close_queue`, `put` returns `false` and `take` drains the remaining items, then returns `none`. If a scope exits early, closing its group cancels consumers blocked in `wait`; they unwind without reacquiring the lock. Never join a consumer while holding the queue's lock.

## Priority queue

`PriorityQueue[T]` lives in the same module as Queue. Construct it with `compare: fn(left: T, right: T) -> Int` and optional `capacity: Optional[Int]`. Negative comparison results put the left item first; ties retain enqueue order. The queue exposes the same enqueue/dequeue/peek/length/is_empty operations and full/empty results as FIFO Queue.

```manuscript
import PriorityQueue from "@std/queues.ms"

fn ascending(left: Int, right: Int) -> Int:
    if left < right: return -1
    if left > right: return 1
    return 0

fn work() -> Unit:
    let pending = PriorityQueue(compare: ascending)
    pending.enqueue(3)
    pending.enqueue(1)
    let first = pending.dequeue()
```

Enqueue/dequeue use a binary heap with logarithmic comparisons. Comparators must define a consistent order and must not mutate the queue. A comparator fault leaves the stored heap unchanged. Like Queue, it has no waiting or cleanup lifecycle; concurrent access requires one Synchronized guard for every operation.
