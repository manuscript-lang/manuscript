import Queue from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import Optional from "@std/optional.ms"
import List from "@std/collections.ms"
import TaskGroup from "@std/tasks.ms"
import panic from "@std/faults.ms"

test "omitted capacity creates an unbounded queue":
    let queue = Queue[Int]()
    let inferred: Queue[Int] = Queue()

    for unused in [1, 2]:
        for value in [
            1,
            2,
            3,
            4,
            5
        ]:
            if not queue.enqueue(value):
                return panic("unbounded queue rejected an item")

        if queue.length() != 5:
            return panic("unbounded queue lost items")

        for value in [
            1,
            2,
            3,
            4,
            5
        ]:
            let expected: Optional[Int] = some(value: value)
            if queue.dequeue() != expected:
                return panic("unbounded queue lost FIFO order")

        let missing: Optional[Int] = none
        if not (queue.is_empty() and queue.dequeue() == missing):
            return panic("unbounded queue did not drain")

    if not inferred.enqueue(1):
        return panic("inferred queue rejected an item")

test "local FIFO aliases and saved methods":
    let queue = Queue[Int](capacity: some(value: 2))
    let alias = queue
    let enqueue = alias.enqueue
    let dequeue = queue.dequeue
    let missing: Optional[Int] = none
    if not (queue.is_empty() and queue.length() == 0):
        return panic("new queue is not empty")
    if not (dequeue() == missing and queue.peek() == missing):
        return panic("empty reads must return none")
    if not (enqueue(3) and enqueue(value: 4)):
        return panic("enqueue failed before capacity")
    if enqueue(5):
        return panic("full queue accepted an item")

    let first: Optional[Int] = some(value: 3)
    let second: Optional[Int] = some(value: 4)
    if not (alias.peek() == first and queue.length() == 2):
        return panic("peek changed the queue")
    if not (dequeue() == first and alias.dequeue() == second):
        return panic("FIFO order changed")
    if not (dequeue() == missing and queue.is_empty()):
        return panic("queue did not drain")
    if not queue.enqueue(4):
        return panic("draining did not free capacity")
    if not (dequeue() == second):
        return panic("drained queue cannot be reused")

test "queue elements include ordinary functions":
    let queue = Queue[fn() -> Int](capacity: some(value: 1))
    queue.enqueue(
        fn() -> Int:
            return 7
    )

    match queue.dequeue():
        some(callback):
            if not (callback() == 7):
                return panic("callback changed")

        none:
            return panic("callback missing")

test "shared queue uses explicit lock scopes":
    let shared = Synchronized(value: Queue[Int]())
    let operation = fn(item: Int) -> Unit:
        for unused in [
            1,
            2,
            3,
            4,
            5
        ]:
            with locked = shared.lock():
                let queue = locked.get()
                if not queue.enqueue(item):
                    return panic("critical section did not drain queue")

                let expected: Optional[Int] = some(value: item)
                if not (queue.dequeue() == expected):
                    return panic("critical section interleaved")
    let task1 = fn() -> Unit:
        operation(item: 1)
    let task2 = fn() -> Unit:
        operation(item: 2)
    let task3 = fn() -> Unit:
        operation(item: 3)
    let task4 = fn() -> Unit:
        operation(item: 4)

    with group = TaskGroup():
        group.start(task1)
        group.start(task2)
        group.start(task3)
        group.start(task4)

        match group.join():
            ok(_):
                with locked = shared.lock():
                    if not locked.get().is_empty():
                        return panic("shared queue did not drain")

            error(_):
                return panic("shared work failed")
