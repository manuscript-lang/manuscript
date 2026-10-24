+++
title = "Task groups"
weight = 1
+++

# Task groups

A `TaskGroup[T]` starts tasks that each return a `T`, and owns them until its `with` block ends. Import it from `@std/tasks.ms`.

<!-- manuscript-example: test -->
```manuscript
from "@std/tasks.ms" import TaskGroup
from "@std/testing.ms" import expect_equal, expect_ok

def square(n: Int) -> Int:
    return n * n

test "a group collects its results in start order":
    with TaskGroup[Int]() as group:
        for n in [1, 2, 3]:
            group.spawn(lambda: square(n))
        group.results() | try expect_ok | try expect_equal([1, 4, 9])
```

## How tasks run

- `spawn(work)` starts `work`, a function with no parameters that returns `T`, and returns a `Task[T]`. The task first runs when the caller waits, in `result()`, `results()`, `wait()` or any call that suspends (sleeping, I/O).
- Tasks share one thread. A task runs until it waits, so a loop that never waits keeps the other tasks from running.
- `task.result()` waits for that task and returns `Result[T, TaskError]`. Call it once per task.
- `group.results()` waits for every started task and returns their results in start order, or the first task's error. `group.wait()` waits for all of them and reports an error if any ended without a result.
- Leaving the `with` block cancels tasks that are still running and waits for them to end. Collect the work first with `results()`, `wait()` or `result()`.
- A task cancelled before it first ran never starts.
- Closing a group invalidates its tasks: `result()` on a task whose group was closed faults, and so does `spawn` on a closed group. A task cannot wait on or close its own group.
- A fault in a task ends the program, as a fault anywhere does.

## Timeouts

A task has no time limit unless you give one. `spawn(work, timeout: some(duration(...)))` limits one task. `TaskGroup[T](timeout: some(duration(...)))` limits every task in the group, counted from the group's creation; a task takes the shorter of the two. A task that passes its limit is cancelled at its next wait, so a loop that never waits is not stopped by its timeout. A task that passes its limit is cancelled, and its `result()` is `error(TaskError.TimedOut)`. A task cancelled any other way gives `TaskError.Cancelled`.

<!-- manuscript-example: test -->
```manuscript
from "@std/tasks.ms" import TaskError, TaskGroup
from "@std/testing.ms" import expect_equal, expect_error
from "@std/time.ms" import duration, sleep

def wait_a_minute() -> Int:
    sleep(duration(60000000000))
    return 1

test "a task that passes its timeout is cancelled":
    with TaskGroup[Int]() as group:
        let task = group.spawn(wait_a_minute, timeout: some(duration(10000000)))
        task.result() | try expect_error | try expect_equal(TaskError.TimedOut)
```

## What a task may use

A spawned function outlives the statement that started it, so it owns what it captures: a captured value moves into the task and the caller can no longer use it. A task cannot change a captured `var`. Return a result instead, and combine results in the caller. Use `.clone()` to keep a copy.

Values reach a task only by being captured, and come back only as its result. Tasks do not share mutable state.
