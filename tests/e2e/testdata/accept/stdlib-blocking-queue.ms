import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"
import BlockingQueue from "@std/queues.ms"
import TaskGroup from "@std/tasks.ms"
import Task from "@std/tasks.ms"

fn work(jobs: BlockingQueue[Int]) Int:
    var total = 0

    while true:
        match jobs.take():
            some(value):
                total = total + value
            none:
                return total

    return total

fn total_of(task: Task[Int]) Result[Int, Error]:
    return ok(try task.join())

test "bounded put and take block until the other side acts":
    let jobs = BlockingQueue[Int](2)

    with group = TaskGroup():
        let first = group.start(fn(): work(jobs: jobs))
        let second = group.start(fn(): work(jobs: jobs))
        for value in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]:
            (jobs.put(value)) | try expect_true
        jobs.close()
        let combined = (try total_of(task: first)) + (try total_of(task: second))
        combined | try expect_equal(expected: 55)

test "close drains queued values then ends takers":
    let jobs = BlockingQueue[Int]()
    (jobs.put(7)) | try expect_true
    jobs.close()
    jobs.close()
    (jobs.is_closed()) | try expect_true
    jobs.put(8) | try expect_false
    jobs.length() | try expect_equal(expected: 1)

    match jobs.take():
        some(value):
            try expect_equal(value, 7)
        none:
            return fail(message: "queued value lost")

    jobs.take().is_some() | try expect_false

test "group close cancels a blocked taker":
    let jobs = BlockingQueue[Int](1)
    with group = TaskGroup():
        group.start(fn(): work(jobs: jobs))
