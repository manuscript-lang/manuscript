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

For concurrent access to a local `Queue`, put the queue in one `Synchronized[Queue[T]]` and hold its guard throughout every operation, including reads. Each caller acquires its own guard from the same wrapper:

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

Wrapping a queue serializes access; it does not by itself add waiting for values or free capacity. For a queue that blocks, use [`BlockingQueue`](#blocking-queue), or call the guard's [`wait()`](synchronization.md#waiting-for-a-change), which releases the lock while sleeping; never poll or spin while holding the lock. Lock acquisition follows the ordinary [Synchronized cancellation and cleanup rules](synchronization.md#synchronized).

## Blocking queue

`BlockingQueue[T]` is a FIFO that waits instead of failing. Import it from `@std/queues.ms`. Omit capacity for an unbounded queue, or supply a positive capacity to bound it. It synchronizes itself, so tasks share it directly with no `Synchronized` wrapper.

```manuscript
fn put(value: T) -> Bool
fn take() -> Optional[T]
fn close() -> Unit
fn length() -> Int
fn is_closed() -> Bool
```

- `put` waits while a bounded queue is full, then appends and returns `true`. It returns `false` once the queue is closed.
- `take` waits while the queue is empty, then removes the oldest value. It returns `none` once the queue is closed and empty.
- `close` stops new puts and wakes every waiting task. Values already queued can still be taken. Closing twice does nothing.
- Waiting holds no lock and stops at [cancellation](cancellation.md): closing a `TaskGroup` cancels workers blocked in `take` or `put`, and they unwind without waiting for the queue.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import BlockingQueue from "@std/queues.ms"
import TaskGroup from "@std/tasks.ms"
import panic from "@std/faults.ms"

fn work(jobs: BlockingQueue[Int]) -> Int:
    var total = 0
    while true:
        match jobs.take():
            some(value):
                total = total + value
            none:
                return total
    return total

test "a producer feeds a worker through a bounded queue":
    let jobs = BlockingQueue[Int](2)
    with group = TaskGroup():
        let worker = group.start(fn(): work(jobs: jobs))
        for value in [1, 2, 3, 4, 5]:
            if not jobs.put(value):
                return panic(message: "put failed")
        jobs.close()
        match worker.join():
            ok(total):
                if not (total == 15):
                    return panic(message: "lost or duplicated items")
            error(_):
                return panic(message: "worker failed")
```

The worker drains what is queued after `close`, then `take` returns `none` and it finishes. Never join a worker from code that the worker is waiting on.

To build a different waiting structure, use the guard's [`wait()` and `notify_all()`](synchronization.md#waiting-for-a-change) on a `Synchronized` value; `BlockingQueue` is built from the same ideas.

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
