import {expect_equal, expect_false, expect_ok, expect_true, fail} from "@std/testing.ms"
import Queue from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import TaskGroup from "@std/tasks.ms"

test "omitted capacity creates an unbounded queue":
    let queue = Queue[Int]()
    let inferred: Queue[Int] = Queue()

    for unused in [1, 2]:
        for value in [1, 2, 3, 4, 5]:
            (queue.enqueue(value)) | try expect_true
        queue.length() | try expect_equal(expected: 5)

        for value in [1, 2, 3, 4, 5]:
            let expected: Optional[Int] = some(value)
            queue.dequeue() | try expect_equal(expected: expected)

        let missing: Optional[Int] = none
        (queue.is_empty() and queue.dequeue() == missing) | try expect_true

    (inferred.enqueue(1)) | try expect_true

test "local FIFO aliases and saved methods":
    let queue = Queue[Int](2)
    let alias = queue
    let enqueue = alias.enqueue
    let dequeue = queue.dequeue
    let missing: Optional[Int] = none
    (queue.is_empty() and queue.length() == 0) | try expect_true
    (dequeue() == missing and queue.peek() == missing) | try expect_true
    (enqueue(3) and enqueue(value: 4)) | try expect_true
    enqueue(5) | try expect_false
    let first: Optional[Int] = some(3)
    let second: Optional[Int] = some(4)
    (alias.peek() == first and queue.length() == 2) | try expect_true
    (dequeue() == first and alias.dequeue() == second) | try expect_true
    (dequeue() == missing and queue.is_empty()) | try expect_true
    (queue.enqueue(4)) | try expect_true
    dequeue() | try expect_equal(expected: second)

test "queue elements include ordinary functions":
    let queue = Queue[fn() Int](1)
    queue.enqueue(
        fn():
            return 7
    )

    match queue.dequeue():
        some(callback):
            try expect_equal(callback(), 7)
        none:
            return fail("callback missing")

test "shared queue uses explicit lock scopes":
    let shared = Synchronized(Queue[Int]())
    let operation = fn(item: Int) Result[Unit, Error]:
        for unused in [1, 2, 3, 4, 5]:
            with locked = shared.lock():
                let queue = locked.get()
                queue.enqueue(item) | try expect_true
                queue.dequeue() | try expect_equal(expected: some(item))

        return ok(unit)

    with group = TaskGroup():
        let tasks = [
            group.start(fn(): operation(1)),
            group.start(fn(): operation(2)),
            group.start(fn(): operation(3)),
            group.start(fn(): operation(4))
        ]
        let joined = try group.join()
        for task in tasks:
            (try task.join()) | try expect_ok
        with locked = shared.lock():
            locked.get().is_empty() | try expect_true
