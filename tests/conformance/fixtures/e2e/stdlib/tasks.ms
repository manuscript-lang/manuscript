# conform: tags=closures,with-cleanup,stdlib-tasks,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
from "@std/collections.ms" import range
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

def slow_square(n: Int) -> Int:
    pause(1)
    return n * n

def leave_early(log: Shared[List[String]]) -> Int:
    with TaskGroup[Unit]() as group:
        let held = log

        group.spawn(
            lambda:
                pause(200)
                record(held, "finished")
        )

        return 7

def wait_for(box: Shared[List[Int]]) -> Int:
    while box.get().length() == 0:
        pause(1)
    return box.get().get(0)

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

test "wait leaves every outcome readable through its handle":
    with TaskGroup[String]() as group:
        let done = group.spawn(lambda: slow(1, "done"))
        let late = group.spawn(
            lambda: slow(2000, "late"), timeout: some(duration(20000000))
        )
        group.wait() | try expect_error | try expect_equal(TaskError.TimedOut)
        done.result() | try expect_ok | try expect_equal("done")
        late.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "results reports the first task that has no result":
    with TaskGroup[String]() as group:
        group.spawn(lambda: slow(1, "done"))
        group.spawn(lambda: slow(2000, "late"), timeout: some(duration(20000000)))
        group.results() | try expect_error | try expect_equal(TaskError.TimedOut)

test "a zero timeout times the task out":
    with TaskGroup[String]() as group:
        let task = group.spawn(lambda: slow(1, "x"), timeout: some(duration(0)))
        task.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "a group whose time has passed times new tasks out":
    with TaskGroup[String](timeout: some(duration(10000000))) as group:
        pause(30)

        let task = group.spawn(lambda: slow(1, "x"))
        task.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "a task that never ran releases what it captured":
    let text = "captured by a task that is cancelled before it runs, long enough for the heap"
    with TaskGroup[String]() as group:
        group.spawn(lambda: text + "!")
    try expect_equal(1, 1)

test "many tasks run and keep their order":
    with TaskGroup[Int]() as group:
        for n in range(0, 300):
            group.spawn(lambda: slow_square(n))

        let results = group.results() | try expect_ok
        try expect_equal(results.length(), 300)
        try expect_equal(results.get(299), 299 * 299)

test "an early exit from the block cancels the tasks":
    let log: Shared[List[String]] = share([])
    try expect_equal(leave_early(log), 7)
    pause(300)
    try expect_equal(log.get().length(), 0)

test "groups nest and close independently":
    with TaskGroup[Int]() as outer:
        let kept = outer.spawn(lambda: square(5))

        with TaskGroup[Int]() as inner:
            let quick = inner.spawn(lambda: square(2))
            quick.result() | try expect_ok | try expect_equal(4)

        kept.result() | try expect_ok | try expect_equal(25)

test "a task can wait for another task's value":
    let box: Shared[List[Int]] = share([])

    with TaskGroup[Int]() as group:
        let producer = box
        let consumer = box

        group.spawn(
            lambda:
                pause(10)

                let empty = producer.take()
                producer.put([42])
                return 0
        )

        let reader = group.spawn(lambda: wait_for(consumer))
        reader.result() | try expect_ok | try expect_equal(42)

test "a task cancelled before it first ran never starts":
    let log: Shared[List[String]] = share([])

    with TaskGroup[Unit]() as group:
        let held = log
        group.spawn(lambda: record(held, "ran"))

    try expect_equal(log.get().length(), 0)

test "closing a group twice leaves a later group alone":
    var first = TaskGroup[Int]()
    first.close()

    with TaskGroup[Int]() as second:
        let task = second.spawn(lambda: slow_square(5))
        first.close()
        task.result() | try expect_ok | try expect_equal(25)

test "more sleeping tasks than the timer heap keeps all finish":
    with TaskGroup[Int]() as group:
        for n in range(0, 1200):
            group.spawn(lambda: slow_square(n))

        let results = group.results() | try expect_ok
        try expect_equal(results.length(), 1200)
