# conform: tags=closures,with-cleanup,stdlib-tasks,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
from "@std/shared.ms" import share, Shared
from "@std/tasks.ms" import TaskError, TaskGroup
from "@std/testing.ms" import expect_equal, expect_error, expect_ok
from "@std/time.ms" import duration, sleep

def pause(milliseconds: Int) -> Unit:
    sleep(duration(milliseconds * 1000000))

def square(n: Int) -> Int:
    return n * n

def slow(milliseconds: Int, label: String) -> String:
    pause(milliseconds)
    return label

def record(log: Shared[List[String]], entry: String) -> Unit:
    let lines = log.take()
    log.put(lines.concat([entry]))

test "results come back in the order the tasks started":
    with TaskGroup[Int]() as group:
        for n in [1, 2, 3, 4]:
            group.spawn(lambda: square(n))
        group.results() | try expect_ok | try expect_equal([1, 4, 9, 16])

test "results do not depend on which task finishes first":
    with TaskGroup[String]() as group:
        group.spawn(lambda: slow(30, "slow"))
        group.spawn(lambda: slow(1, "fast"))
        group.results() | try expect_ok | try expect_equal(["slow", "fast"])

test "a task handle returns its own result":
    with TaskGroup[Int]() as group:
        let first = group.spawn(lambda: square(3))
        let second = group.spawn(lambda: square(4))
        second.result() | try expect_ok | try expect_equal(16)
        first.result() | try expect_ok | try expect_equal(9)

test "tasks switch while one waits":
    let log: Shared[List[String]] = share([])

    with TaskGroup[Unit]() as group:
        let first = log
        let second = log

        group.spawn(
            lambda:
                pause(30)
                record(first, "late")
        )

        group.spawn(lambda: record(second, "early"))
        group.wait() | try expect_ok

    try expect_equal(log.get().clone(), ["early", "late"])

test "a task owns the values its closure captures":
    let greeting = "hello from a task, long enough for the heap"

    with TaskGroup[String]() as group:
        group.spawn(lambda: greeting + "!")
        group.results() | try expect_ok | try expect_equal(
            ["hello from a task, long enough for the heap!"]
        )

test "leaving the block cancels tasks that are still running":
    let log: Shared[List[String]] = share([])

    with TaskGroup[Unit]() as group:
        let held = log

        group.spawn(
            lambda:
                pause(200)
                record(held, "finished")
        )

    pause(300)
    try expect_equal(log.get().length(), 0)

test "an empty group has no results":
    with TaskGroup[Int]() as group:
        group.results() | try expect_ok | try expect_equal(List[Int]())

test "a task that passes its timeout is cancelled":
    with TaskGroup[String]() as group:
        let late = group.spawn(
            lambda: slow(2000, "late"), timeout: some(duration(20000000))
        )
        let quick = group.spawn(
            lambda: slow(1, "quick"), timeout: some(duration(2000000000))
        )
        late.result() | try expect_error | try expect_equal(TaskError.TimedOut)
        quick.result() | try expect_ok | try expect_equal("quick")

test "a group timeout limits every task started in it":
    with TaskGroup[String](timeout: some(duration(50000000))) as group:
        let late = group.spawn(lambda: slow(2000, "late"))
        let early = group.spawn(lambda: slow(1, "early"))
        early.result() | try expect_ok | try expect_equal("early")
        late.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "a task shorter than its group limit uses its own limit":
    with TaskGroup[String](timeout: some(duration(2000000000))) as group:
        let late = group.spawn(
            lambda: slow(2000, "late"), timeout: some(duration(20000000))
        )
        late.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "wait reports a task that timed out":
    with TaskGroup[String]() as group:
        group.spawn(lambda: slow(2000, "late"), timeout: some(duration(20000000)))
        group.wait() | try expect_error | try expect_equal(TaskError.TimedOut)

test "a task without a timeout runs to its end":
    with TaskGroup[String]() as group:
        group.spawn(lambda: slow(60, "done"))
        group.results() | try expect_ok | try expect_equal(["done"])
