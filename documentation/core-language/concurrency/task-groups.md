+++
title = "Task groups"
weight = 1
+++

# Task groups

A `TaskGroup[T]` starts tasks that each return a `T`, and owns them until its `with` block ends. Import it from `@std/tasks.ms`. Each task also gets a two-way [channel](#channels) to the group.

<!-- manuscript-example: test -->
```manuscript
from "@std/tasks.ms" import TaskGroup
from "@std/testing.ms" import expect_equal, expect_ok

def square(n: Int) -> Int:
    return n * n

test "a group collects its results in start order":
    with let group = TaskGroup[Int]():
        for n in [1, 2, 3]:
            group.spawn(lambda ch: square(n))
        group.results() | try expect_ok | try expect_equal([1, 4, 9])
```

## How tasks run

- `spawn(entry)` starts `entry`, a function that takes the task's end of its channel and returns `T`, and returns a `Task[T]`. A task that sends no messages ignores its channel: `lambda ch: square(n)`. The task first runs when the caller waits, in `result()`, `results()`, `wait()` or any call that suspends (sleeping, I/O).
- Tasks share one thread. A task runs until it waits (including on a channel), so a loop that never waits keeps the other tasks from running.
- `task.result()` waits for that task and returns `Result[T, TaskError]`. Call it once per task.
- `group.results()` waits for every uncollected task and returns their results in start order, or the first task's error. A task collected with `result()` is not included. Collecting a task, by `result()` or `results()`, makes the group forget it, so a long-lived group holds only tasks that are running or uncollected. `group.wait()` waits for all of them and reports an error if any ended without a result.
- Leaving the `with` block cancels tasks that are still running and waits for them to end. Collect the work first with `results()`, `wait()` or `result()`.
- A task cancelled before it first ran never starts.
- A task cancelled while it waits releases the values its functions own, as if it had returned: lists, strings and maps are freed, and `with` blocks close. A value held only in a `var` that a call is changing at that moment, or in a runtime-native resource without a `with` close, can outlive the task until the program ends.
- Closing a group invalidates its tasks: afterwards `result()`, `wait()`, `results()` and `spawn` give `TaskError.Closed` instead of a result. A second `result()` on the same task gives `Closed` too. A task cannot wait on or close its own group.
- A fault in a task ends the program, as a fault anywhere does.

## Timeouts

A task has no time limit unless you give one. `spawn(entry, timeout: some(duration(...)))` limits one task. `TaskGroup[T](timeout: some(duration(...)))` limits every task in the group, counted from the group's creation; a task takes the shorter of the two. A task that passes its limit is cancelled at its next wait, so a loop that never waits is not stopped by its timeout. A task that passes its limit is cancelled, and its `result()` is `error(TaskError.TimedOut)`. A task cancelled any other way gives `TaskError.Cancelled`. `TaskError.Closed` means the task's group was closed or its result was already collected.

<!-- manuscript-example: test -->
```manuscript
from "@std/channels.ms" import Channel
from "@std/tasks.ms" import TaskError, TaskGroup
from "@std/testing.ms" import expect_equal, expect_error
from "@std/time.ms" import duration, sleep

def wait_a_minute(ch: Channel[Unit, Unit]) -> Int:
    sleep(duration(60000000000))
    return 1

test "a task that passes its timeout is cancelled":
    with let group = TaskGroup[Int]():
        let task = group.spawn(wait_a_minute, timeout: some(duration(10000000)))
        task.result() | try expect_error | try expect_equal(TaskError.TimedOut)
```

## What a task may use

A spawned function outlives the statement that started it, so it owns what it captures: a captured value moves into the task and the caller can no longer use it. A task cannot change a captured `var`. Return a result instead, and combine results in the caller. Use `.clone()` to keep a copy.

Values reach a task by being captured or sent on its channel, and come back as messages or as its result. Tasks do not share mutable state.

## Channels

`TaskGroup[T, In, Out]` gives every task a channel that carries `In` values to the task and `Out` values back; both are `Unit` unless given. `Channel` comes from `@std/channels.ms`. The task's entry takes a `Channel[Out, In]`, and the `Task[T, In, Out]` that `spawn` returns holds the group's end, a `Channel[In, Out]`, in its `channel` field.

<!-- manuscript-example: test -->
```manuscript
from "@std/channels.ms" import Channel, ChannelError
from "@std/tasks.ms" import TaskGroup
from "@std/testing.ms" import expect_equal, expect_ok

def square_all(ch: Channel[Int, Int]) -> Result[Unit, ChannelError]:
    var c = ch
    while True:
        if let n = try c.receive():
            try c.send(n * n)
        else:
            return ok(())
    return ok(())

test "a task answers messages on its channel":
    with let group = TaskGroup[Result[Unit, ChannelError], Int, Int]():
        var task = group.spawn(square_all)
        task.channel.send(3) | try expect_ok
        task.channel.receive() | try expect_ok | try expect_equal(some(9))
        task.channel.close()
        task.result() | try expect_ok | try expect_ok
```

- `send(value)` moves `value` to the other end. It waits while the other end has 16 unread values.
- `receive()` waits for the next value: `ok(some(value))`, or `ok(none)` once the other end closed and every value it sent was read.
- `close()` closes this end. The other end reads what is left, then `ok(none)`; its sends give `error(ChannelError.Closed)`. Using an end after closing it gives `Closed`, and unread values on it are dropped. Closing again does nothing.
- A task's end closes when its entry returns, is cancelled, or never ran, so the group's `receive` ends with `ok(none)` instead of waiting forever. Closing the group closes every end.
- Two tasks that each wait to send to the other while neither reads wait forever; when every task waits like this the program stops with a deadlock fault.
- An end has one owner. `.clone()` makes another handle on the same end, so several tasks can send to or receive from it.
- Write the parameter as `ch` and rebind it with `var c = ch`; a function with a `var` parameter cannot be passed as an entry yet ([#1191](https://github.com/manuscript-lang/manuscript/issues/1191)).
