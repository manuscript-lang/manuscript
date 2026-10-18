import {expect_equal, expect_error, expect_false} from "@std/testing.ms"
import {Queue, PriorityQueue} from "@std/queues.ms"
import Synchronized from "@std/sync.ms"
import {Scheduler, StartError, WorkStatus, check_cancelled, yield_now, TaskGroup} from "@std/tasks.ms"

fn compare(left: Int, right: Int) Int: left - right

fn operation() Result[Unit, Error]: ok(unit)

fn first() Int: 1

fn second() String: "two"

test "FIFO capacity empty reads draining and reuse":
    let queue = Queue[Int](2)
    try expect_false(not queue.is_empty() or not queue.peek().is_none())
    try expect_false((not queue.enqueue(1) or not queue.enqueue(2) or queue.enqueue(3)))
    try expect_false(queue.peek() != some(1) or queue.length() != 2)
    try expect_false(queue.dequeue() != some(1) or queue.dequeue() != some(2))
    try expect_false(not queue.dequeue().is_none() or not queue.enqueue(4))

test "priority queue orders values and honors capacity":
    let queue = PriorityQueue(compare, 3)
    queue.enqueue(3)
    queue.enqueue(1)
    queue.enqueue(2)
    try expect_false(queue.enqueue(0))
    try expect_equal(queue.peek(), some(1))
    for expected in [1, 2, 3]:
        try expect_equal(queue.dequeue(), some(expected))
    try expect_false(not queue.is_empty())

test "synchronized guards update and release for later acquisition":
    let state = Synchronized(1)

    with guard = state.lock():
        try expect_equal(guard.get(), 1)
        guard.set(2)

    with guard = state.lock():
        try expect_equal(guard.get(), 2)

test "scheduler delayed cancellation capacity and closed admission":
    let scheduler = Scheduler(1)
    let id = try scheduler.after(60.seconds, operation)
    try expect_equal(scheduler.status(id), WorkStatus.Running)
    try expect_equal((try expect_error(scheduler.start(operation))), StartError.Full)
    scheduler.cancel(id)
    scheduler.close()
    try expect_equal(scheduler.status(id), WorkStatus.Cancelled)
    scheduler.close()
    try expect_equal((try expect_error(scheduler.start(operation))), StartError.Closed)

test "task group heterogeneous results and cancellation checkpoints":
    check_cancelled()
    yield_now()

    with tasks = TaskGroup():
        let number_task = tasks.start(first)
        let text_task = tasks.start(second)
        try tasks.join()
        let number = try number_task.join()
        let text = try text_task.join()
        try expect_false(number != 1 or text != "two")
