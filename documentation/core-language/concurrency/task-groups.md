+++
title = "Task groups"
weight = 1
+++

# Task groups

A `TaskGroup[T]` starts tasks that each return a `T`, and owns them until its scope ends. Import it from `@std/concurrency/tasks.ms`. Each task also gets a two-way [channel](#channels) to the group.

<!-- manuscript-example: test -->
```manuscript
import TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal, expect_ok from "@std/test/test.ms"

fn square(n: Int) Int:
    return n * n

test "a group collects its results in start order":
    let group = TaskGroup[Int]()
    for n in [1, 2, 3]:
        group.spawn(fn ch: square(n))
    group.results() | try expect_ok | try expect_equal([1, 4, 9])
```

## How tasks run

- `spawn(entry)` starts `entry`, a function that takes the task's end of its channel and returns `T`, and returns a `Task[T]`. A task that sends no messages ignores its channel: `fn ch: square(n)`. The task first runs when the caller waits, in `result()`, `results()`, `wait()` or any call that suspends (sleeping, I/O).
- Tasks share one thread. A task runs until it waits (including on a channel), so a loop that never waits keeps the other tasks from running.
- `task.result()` waits for that task and returns `T!`. Call it once per task.
- `group.results()` waits for every uncollected task and returns their results in start order, or the first task's error. A task collected with `result()` is not included. Collecting a task, by `result()` or `results()`, makes the group forget it, so a long-lived group holds only tasks that are running or uncollected. `group.wait()` waits for all of them and reports an error if any ended without a result.
- Leaving the scope of the group binding cancels tasks that are still running and waits for them to end. Collect the work first with `results()`, `wait()` or `result()`.
- A task cancelled before it first ran never starts.
- Files, connections and other resources bound inside a task close when the task leaves their scope. Cancellation is not a guarantee that every allocation is reclaimed; some stack-held values and native resources can remain until program exit.
- Closing a group invalidates its tasks: afterwards `result()`, `wait()`, `results()` and `spawn` give an `Error` of kind `Closed` instead of a result. A second `result()` on the same task gives kind `Closed` too. A task cannot wait on or close its own group.
- A Manuscript fault in a task ends the program, unless the group is created with `contain_faults: true`: then only that task ends, its siblings keep running, and `result()`, `results()` or `wait()` return an `Error` of kind `Failed`, where `details["report"]` is the fault text with frames. Fault containment does not guarantee complete resource reclamation. A faulted task that is never collected is dropped when the group closes, with no report.
- A Manuscript fault in a task on the main thread otherwise ends the program. When the worker runtime catches a Manuscript fault from a task inside that worker, its starter observes it through `worker.wait()`. This does not isolate native crashes from the rest of the process.

## Timeouts

A task has no time limit unless you give one. `spawn(entry, timeout: nanoseconds(...))` limits one task. `TaskGroup[T](timeout: nanoseconds(...))` limits every task in the group, counted from the group's creation; a task takes the shorter of the two. A task that passes its limit is cancelled at its next wait, so a loop that never waits is not stopped by its timeout. A task that passes its limit is cancelled, and its `result()` is an `Error` of kind `Timeout`. A task cancelled any other way gives an `Error` with message `task: cancelled`. Kind `Closed` means the task's group was closed or its result was already collected.

<!-- manuscript-example: test -->
```manuscript
import Channel from "@std/io/channels.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal, expect_error from "@std/test/test.ms"
import nanoseconds, sleep from "@std/os/time.ms"

fn wait_a_minute(ch: Channel[Unit, Unit]) Int:
    sleep(nanoseconds(60000000000))
    return 1

test "a task that passes its timeout is cancelled":
    let group = TaskGroup[Int]()
    let task = group.spawn(wait_a_minute, timeout: nanoseconds(10000000))
    let timed_out = task.result() | try expect_error
    timed_out.kind | try expect_equal(ErrorCategory.Timeout)
```

`cancelled()` from `@std/concurrency/tasks.ms` returns `true` once the running task was cancelled, by a closed group, a passed timeout or a program stop. It only reports: it does not wait or unwind, so a loop that never waits can poll it and return early. It stays `true` inside scope-end cleanups.

## What a task may use

A spawned function outlives the statement that started it, so it owns what it captures: a captured value moves into the task when this is its last use, and is copied into the task when the caller uses it again. A function value or a resource cannot be copied, so those must be the last use. A task cannot change a captured `var`. Return a result instead, and combine results in the caller.

Values reach a task by being captured or sent on its channel, and come back as messages or as its result. Tasks do not share mutable state.

## Channels

`TaskGroup[T, In, Out]` gives every task a channel that carries `In` values to the task and `Out` values back; both are `Unit` unless given. `Channel` comes from `@std/io/channels.ms`. The task's entry takes a `Channel[Out, In]`, and the `Task[T, In, Out]` that `spawn` returns holds the group's end, a `Channel[In, Out]`, in its `channel` field.

<!-- manuscript-example: test -->
```manuscript
import Channel from "@std/io/channels.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal, expect_ok from "@std/test/test.ms"

fn square_all(ch: Channel[Int, Int]) Unit!:
    var c = ch
    while true:
        if let n = try c.receive():
            try c.send(n * n)
        else:
            return ok(unit)
    return ok(unit)

test "a task answers messages on its channel":
    let group = TaskGroup[Unit!, Int, Int]()
    var task = group.spawn(square_all)
    task.channel.send(3) | try expect_ok
    task.channel.receive() | try expect_ok | try expect_equal(9)
    task.channel.close()
    task.result() | try expect_ok | try expect_ok
```

- `send(value)` moves `value` to the other end. It waits while the other end has 16 unread values.
- `receive()` waits for the next value: `ok(value)`, or `ok(none)` once the other end closed and every value it sent was read.
- `close()` closes this end. The other end reads what is left, then `ok(none)`; its sends give an `Error` of kind `Closed`. Using an end after closing it gives kind `Closed`, and unread values on it are dropped. Closing again does nothing.
- A task's end closes when its entry returns, is cancelled, or never ran, so the group's `receive` ends with `ok(none)` instead of waiting forever. Closing the group closes every end.
- Collecting a task's result leaves its channel readable, including buffered values. Closing the group closes retained and cloned channel handles too, even after result collection, and drops their unread values. Discarded collected channels are released without waiting for group close or another spawn.
- Two tasks that each wait to send to the other while neither reads cannot make progress. The task scheduler can detect deadlocks within its own scheduler. Cycles spanning workers or processes are not covered by this guarantee; design protocols so each receive has a corresponding sender.
- An end has one owner. `.clone()` makes another handle on the same end, so several tasks can send to or receive from it.
- Write the parameter as `ch` and rebind it with `var c = ch`; a function with a `var` parameter cannot be passed as an entry yet ([#1191](https://github.com/manuscript-lang/manuscript/issues/1191)).
