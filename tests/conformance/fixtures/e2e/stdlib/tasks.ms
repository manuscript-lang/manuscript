# conform: tags=closures,scope-cleanup,stdlib-tasks,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
import share, Shared, lock from "@std/concurrency/shared.ms"
import TaskError, TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal, expect_error, expect_ok from "@std/test/test.ms"
import nanoseconds, sleep from "@std/os/time.ms"

fn pause(milliseconds: Int) Unit:
    sleep(nanoseconds(milliseconds * 1000000))

fn square(n: Int) Int:
    return n * n

fn slow(milliseconds: Int, label: String) String:
    pause(milliseconds)
    return label

fn record(log: Shared[List[String]], entry: String) Unit:
    var lines = lock(log)
    lines.value.append(entry)

fn slow_square(n: Int) Int:
    pause(1)
    return n * n

fn leave_early(log: Shared[List[String]]) Int:
    let group = TaskGroup[Unit]()
    let held = log

    group.spawn(
        fn ch:
            pause(200)
            record(held, "finished")
    )

    return 7

fn wait_for(box: Shared[List[Int]]) Int:
    while box.get().length() == 0:
        pause(1)
    return box.get().get(0)

test "results come back in the order the tasks started":
    let group = TaskGroup[Int]()
    for n in [1, 2, 3, 4]:
        group.spawn(fn ch: square(n))
    group.results() | try expect_ok | try expect_equal([1, 4, 9, 16])

test "results do not depend on which task finishes first":
    let group = TaskGroup[String]()
    group.spawn(fn ch: slow(30, "slow"))
    group.spawn(fn ch: slow(1, "fast"))
    group.results() | try expect_ok | try expect_equal(["slow", "fast"])

test "a task handle returns its own result":
    let group = TaskGroup[Int]()
    let first = group.spawn(fn ch: square(3))
    let second = group.spawn(fn ch: square(4))
    second.result() | try expect_ok | try expect_equal(16)
    first.result() | try expect_ok | try expect_equal(9)

test "tasks switch while one waits":
    let log: Shared[List[String]] = share([])
    var group = TaskGroup[Unit]()
    let first = log
    let second = log

    group.spawn(
        fn ch:
            pause(30)
            record(first, "late")
    )

    group.spawn(fn ch: record(second, "early"))
    group.wait() | try expect_ok
    try group.close()
    try expect_equal(log.get().clone(), ["early", "late"])

test "a task owns the values its closure captures":
    let greeting = "hello from a task, long enough for the heap"
    let group = TaskGroup[String]()
    group.spawn(fn ch: greeting + "!")
    group.results() | try expect_ok | try expect_equal(
        ["hello from a task, long enough for the heap!"]
    )

test "leaving the block cancels tasks that are still running":
    let log: Shared[List[String]] = share([])
    var group = TaskGroup[Unit]()
    let held = log

    group.spawn(
        fn ch:
            pause(200)
            record(held, "finished")
    )

    try group.close()
    pause(300)
    try expect_equal(log.get().length(), 0)

test "an empty group has no results":
    let group = TaskGroup[Int]()
    group.results() | try expect_ok | try expect_equal(List[Int]())

test "a task that passes its timeout is cancelled":
    let group = TaskGroup[String]()
    let late = group.spawn(fn ch: slow(2000, "late"), timeout: nanoseconds(20000000))
    let quick = group.spawn(fn ch: slow(1, "quick"), timeout: nanoseconds(2000000000))
    late.result() | try expect_error | try expect_equal(TaskError.TimedOut)
    quick.result() | try expect_ok | try expect_equal("quick")

test "a group timeout limits every task started in it":
    let group = TaskGroup[String](timeout: nanoseconds(50000000))
    let late = group.spawn(fn ch: slow(2000, "late"))
    let early = group.spawn(fn ch: slow(1, "early"))
    early.result() | try expect_ok | try expect_equal("early")
    late.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "a task shorter than its group limit uses its own limit":
    let group = TaskGroup[String](timeout: nanoseconds(2000000000))
    let late = group.spawn(fn ch: slow(2000, "late"), timeout: nanoseconds(20000000))
    late.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "wait reports a task that timed out":
    let group = TaskGroup[String]()
    group.spawn(fn ch: slow(2000, "late"), timeout: nanoseconds(20000000))
    group.wait() | try expect_error | try expect_equal(TaskError.TimedOut)

test "a task without a timeout runs to its end":
    let group = TaskGroup[String]()
    group.spawn(fn ch: slow(60, "done"))
    group.results() | try expect_ok | try expect_equal(["done"])

test "wait leaves every outcome readable through its handle":
    let group = TaskGroup[String]()
    let done = group.spawn(fn ch: slow(1, "done"))
    let late = group.spawn(fn ch: slow(2000, "late"), timeout: nanoseconds(20000000))
    group.wait() | try expect_error | try expect_equal(TaskError.TimedOut)
    done.result() | try expect_ok | try expect_equal("done")
    late.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "results reports the first task that has no result":
    let group = TaskGroup[String]()
    group.spawn(fn ch: slow(1, "done"))
    group.spawn(fn ch: slow(2000, "late"), timeout: nanoseconds(20000000))
    group.results() | try expect_error | try expect_equal(TaskError.TimedOut)

test "a zero timeout times the task out":
    let group = TaskGroup[String]()
    let task = group.spawn(fn ch: slow(1, "x"), timeout: nanoseconds(0))
    task.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "a group whose time has passed times new tasks out":
    let group = TaskGroup[String](timeout: nanoseconds(10000000))
    pause(30)

    let task = group.spawn(fn ch: slow(1, "x"))
    task.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "a task that never ran releases what it captured":
    let text = "captured by a task that is cancelled before it runs, long enough for the heap"
    var group = TaskGroup[String]()
    group.spawn(fn ch: text + "!")
    try group.close()
    try expect_equal(1, 1)

test "many tasks run and keep their order":
    let group = TaskGroup[Int]()
    for n in 0..300:
        group.spawn(fn ch: slow_square(n))

    let results = group.results() | try expect_ok
    try expect_equal(results.length(), 300)
    try expect_equal(results.get(299), 299 * 299)

test "an early exit from the block cancels the tasks":
    let log: Shared[List[String]] = share([])
    try expect_equal(leave_early(log), 7)
    pause(300)
    try expect_equal(log.get().length(), 0)

test "groups nest and close independently":
    let outer = TaskGroup[Int]()
    let kept = outer.spawn(fn ch: square(5))
    var inner = TaskGroup[Int]()
    let quick = inner.spawn(fn ch: square(2))
    quick.result() | try expect_ok | try expect_equal(4)
    try inner.close()
    kept.result() | try expect_ok | try expect_equal(25)

test "a task can wait for another task's value":
    let box: Shared[List[Int]] = share([])
    let group = TaskGroup[Int]()
    let producer = box
    let consumer = box

    group.spawn(
        fn ch:
            pause(10)

            var items = lock(producer)
            items.value.append(42)
            items.close().get(none)
            return 0
    )

    let reader = group.spawn(fn ch: wait_for(consumer))
    reader.result() | try expect_ok | try expect_equal(42)

test "a task cancelled before it first ran never starts":
    let log: Shared[List[String]] = share([])
    var group = TaskGroup[Unit]()
    let held = log
    group.spawn(fn ch: record(held, "ran"))
    try group.close()
    try expect_equal(log.get().length(), 0)

test "closing a group twice leaves a later group alone":
    var first = TaskGroup[Int]()
    try first.close()

    let second = TaskGroup[Int]()
    let task = second.spawn(fn ch: slow_square(5))
    try first.close()
    task.result() | try expect_ok | try expect_equal(25)

test "more sleeping tasks than the timer heap keeps all finish":
    let group = TaskGroup[Int]()
    for n in 0..1200:
        group.spawn(fn ch: slow_square(n))

    let results = group.results() | try expect_ok
    try expect_equal(results.length(), 1200)

test "using a task after its group closed gives Closed":
    var group = TaskGroup[Int]()
    let task = group.spawn(fn ch: slow_square(3))
    try group.close()
    task.result() | try expect_error | try expect_equal(TaskError.Closed)
    (
        group.spawn(
            fn ch: slow_square(4)
        ).result() | try expect_error | try expect_equal(TaskError.Closed)
    )
    group.wait() | try expect_error | try expect_equal(TaskError.Closed)
    group.results() | try expect_error | try expect_equal(TaskError.Closed)

test "a second result call gives Closed":
    let group = TaskGroup[Int]()
    let task = group.spawn(fn ch: square(2))
    task.result() | try expect_ok | try expect_equal(4)
    task.result() | try expect_error | try expect_equal(TaskError.Closed)

test "a group forgets collected tasks":
    let group = TaskGroup[Int]()
    let first = group.spawn(fn ch: square(2))
    let second = group.spawn(fn ch: square(3))
    let third = group.spawn(fn ch: square(4))
    second.result() | try expect_ok | try expect_equal(9)
    group.results() | try expect_ok | try expect_equal([4, 16])
    first.result() | try expect_error | try expect_equal(TaskError.Closed)
    third.result() | try expect_error | try expect_equal(TaskError.Closed)
    group.results() | try expect_ok | try expect_equal([])

test "a group with a timeout collects many tasks":
    let group = TaskGroup[Int](timeout: nanoseconds(3600000000000))
    var total = 0
    for i in 0..5000:
        total += group.spawn(fn ch: i).result().get(0)
    total | try expect_equal(12497500)
