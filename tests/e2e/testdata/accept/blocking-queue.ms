import Queue from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import TaskGroup from "@std/tasks.ms"
import Task from "@std/tasks.ms"
import panic from "@std/faults.ms"

type QueueState:
    items: Queue[Int]
    closed: Bool

fn put(state: Synchronized[QueueState], value: Int) -> Bool:
    with locked = state.lock():
        while true:
            let current = locked.get()
            if current.closed:
                return false

            if current.items.enqueue(value):
                locked.notify_all()
                return true

            locked.wait()

    return false

fn take(state: Synchronized[QueueState]) -> Optional[Int]:
    with locked = state.lock():
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

fn close_queue(state: Synchronized[QueueState]) -> Unit:
    with locked = state.lock():
        let current = locked.get()
        current.closed = true
        locked.notify_all()

fn drain(state: Synchronized[QueueState]) -> Int:
    var total = 0

    while true:
        match take(state: state):
            some(value):
                total = total + value
            none:
                return total

    return total

fn try_total(task: Task[Int]) -> Int:
    match task.join():
        ok(total):
            return total
        error(_):
            return panic(message: "consumer failed")

test "bounded producer and consumers block and finish":
    let state = Synchronized(
        QueueState(
            items: Queue[Int](2),
            closed: false
        )
    )

    with group = TaskGroup():
        let first = group.start(
            fn(): drain(state: state)
        )
        let second = group.start(
            fn(): drain(state: state)
        )

        for value in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
            if not put(state: state, value: value):
                return panic(message: "put failed")

        close_queue(state: state)
        let left = try_total(task: first)
        let right = try_total(task: second)
        if not (left + right == 55):
            return panic(message: "lost or duplicated items")

test "group close cancels a blocked consumer":
    let state = Synchronized(
        QueueState(
            items: Queue[Int](2),
            closed: false
        )
    )

    with group = TaskGroup():
        group.start(
            fn(): drain(state: state)
        )
