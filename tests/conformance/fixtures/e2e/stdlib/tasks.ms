# conform: tags=closures,with-cleanup,stdlib-tasks,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
from "@std/shared.ms" import share, Shared
from "@std/tasks.ms" import TaskGroup
from "@std/testing.ms" import expect_equal
from "@std/time.ms" import duration, sleep

def pause(milliseconds: Int) -> Unit:
    sleep(duration(milliseconds * 1000000))

def square(n: Int) -> Int:
    return n * n

def slow(milliseconds: Int, label: String) -> String:
    pause(milliseconds)
    return label

def record(log: Shared[List[String]], entry: String) -> Unit:
    var lines = log.take()
    lines.append(entry)
    log.put(lines)

test "results come back in the order the tasks started":
    with TaskGroup[Int]() as group:
        for n in [1, 2, 3, 4]:
            group.spawn(lambda: square(n))
        try expect_equal(group.results(), [1, 4, 9, 16])

test "results do not depend on which task finishes first":
    with TaskGroup[String]() as group:
        group.spawn(lambda: slow(30, "slow"))
        group.spawn(lambda: slow(1, "fast"))
        try expect_equal(group.results(), ["slow", "fast"])

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
        group.results()

    try expect_equal(log.get().clone(), ["early", "late"])

test "a task owns the values its closure captures":
    let greeting = "hello from a task, long enough for the heap"

    with TaskGroup[String]() as group:
        group.spawn(lambda: greeting + "!")
        try expect_equal(
            group.results(), ["hello from a task, long enough for the heap!"]
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
        try expect_equal(group.results(), List[Int]())
