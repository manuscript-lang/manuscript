+++
title = "Task groups"
weight = 1
+++

# Task groups

A `TaskGroup[T]` starts tasks that each return a `T`, and owns them until its `with` block ends. Import it from `@std/tasks.ms`.

<!-- manuscript-example: test -->
```manuscript
from "@std/tasks.ms" import TaskGroup
from "@std/testing.ms" import expect_equal

def square(n: Int) -> Int:
    return n * n

test "a group collects its results in start order":
    with TaskGroup[Int]() as group:
        for n in [1, 2, 3]:
            group.spawn(lambda: square(n))
        try expect_equal(group.results(), [1, 4, 9])
```

## How tasks run

- `spawn(work)` starts `work`, a function with no parameters that returns `T`. The task first runs when the caller waits, in `results()` or in any call that suspends (sleeping, I/O).
- Tasks share one thread. A task runs until it waits, so a loop that never waits keeps the other tasks from running.
- `results()` waits for every started task and returns their results in start order, whichever finished first.
- Leaving the `with` block cancels tasks that are still running and waits for them to end. Call `results()` before the block ends to keep their work.
- A fault in a task ends the program, as a fault anywhere does.

## What a task may use

A spawned function outlives the statement that started it, so it owns what it captures: a captured value moves into the task and the caller can no longer use it. A task cannot change a captured `var`. Return a result instead, and combine results in the caller. Use `.clone()` to keep a copy.

Values reach a task only by being captured, and come back only as its result. Tasks do not share mutable state.
