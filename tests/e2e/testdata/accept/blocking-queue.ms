import Queue from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import TaskGroup from "@std/tasks.ms"
import Task from "@std/tasks.ms"
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
            let current = locked.value
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
            let current = locked.value
            let item = current.items.dequeue()

            if item.is_some:
                locked.notify_all()
                return item

            if current.closed:
                return none

            locked.wait()

    return none

# Stops new puts and wakes every waiting task. Queued values can still be taken.
fn close_queue[T](queue: BlockingQueue[T]) -> Unit:
    with locked = queue.state.lock():
        let current = locked.value
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

fn total_of(task: Task[Int]) -> Int:
    match task.join():
        ok(total):
            return total
        error(_):
            return panic(message: "consumer failed")

test "bounded producer and consumers block and finish":
    let queue = new_blocking_queue[Int](2)

    with group = TaskGroup():
        let first = group.start(fn(): work(queue: queue))
        let second = group.start(fn(): work(queue: queue))

        for value in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
            if not put(queue: queue, value: value):
                return panic(message: "put failed")

        close_queue(queue: queue)
        let left = total_of(task: first)
        let right = total_of(task: second)
        if not (left + right == 55):
            return panic(message: "lost or duplicated items")

test "group close cancels a blocked consumer":
    let queue = new_blocking_queue[Int](2)

    with group = TaskGroup():
        group.start(fn(): work(queue: queue))
