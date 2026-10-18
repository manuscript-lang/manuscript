import {expect_equal, expect_false, expect_ok, expect_true, fail} from "@std/testing.ms"
import {Queue, PriorityQueue} from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import {Scheduler, StartError, WorkStatus, check_cancelled, yield_now, TaskGroup} from "@std/tasks.ms"
import {ListBuilder} from "@std/collections.ms"

fn compare(left: Int, right: Int) -> Int: left - right

fn operation() -> Result[Unit, Error]: ok(unit)

fn first() -> Int: 1

fn second() -> String: "two"

test "FIFO capacity empty reads draining and reuse":
    let queue = Queue[Int](2)
    (not queue.is_empty() or not queue.peek().is_none()) | try expect_false
    (not queue.enqueue(1) or not queue.enqueue(2) or queue.enqueue(3)) | try expect_false
    (queue.peek() != some(1) or queue.length() != 2) | try expect_false
    (queue.dequeue() != some(1) or queue.dequeue() != some(2)) | try expect_false
    (not queue.dequeue().is_none() or not queue.enqueue(4)) | try expect_false

test "priority queue orders values and honors capacity":
    let queue = PriorityQueue(compare: compare, capacity: 3)
    queue.enqueue(3)
    queue.enqueue(1)
    queue.enqueue(2)
    queue.enqueue(0) | try expect_false
    queue.peek() | try expect_equal(expected: some(1))
    for expected in [1, 2, 3]:
        queue.dequeue() | try expect_equal(expected: some(expected))
    (queue.is_empty()) | try expect_true

test "synchronized guards update and release for later acquisition":
    let state = Synchronized(1)

    with guard = state.lock():
        guard.get() | try expect_equal(expected: 1)
        guard.set(2)

    with guard = state.lock():
        guard.get() | try expect_equal(expected: 2)

test "scheduler delayed cancellation capacity and closed admission":
    let scheduler = Scheduler(limit: 1)
    let id = (
        scheduler.after(
            duration: 60.seconds,
            operation: operation
        ) | try expect_ok
    )
    scheduler.status(id) | try expect_equal(expected: WorkStatus.Running)

    match scheduler.start(operation):
        ok(_): return fail("scheduler capacity ignored")
        error(cause):
            try expect_equal(cause, StartError.Full)

    scheduler.cancel(id)
    scheduler.close()
    scheduler.status(id) | try expect_equal(expected: WorkStatus.Cancelled)
    scheduler.close()

    match scheduler.start(operation):
        ok(_): return fail("closed scheduler admitted work")
        error(cause):
            try expect_equal(cause, StartError.Closed)

test "task group heterogeneous results and cancellation checkpoints":
    check_cancelled()
    yield_now()

    with tasks = TaskGroup():
        let number_task = tasks.start(first)
        let text_task = tasks.start(second)
        let completed = (tasks.join() | try expect_ok)
        let number = (number_task.join() | try expect_ok)
        let text = (text_task.join() | try expect_ok)
        (number != 1 or text != "two") | try expect_false
