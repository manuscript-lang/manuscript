+++
title = "Process groups"
weight = 2
+++

# Process groups

A `ProcessGroup[T, In, Out]` runs functions of your program in child processes and owns them until its scope ends. Import it from `@std/os/processes.ms`. It has the same shape as a [task group](task-groups.md): `spawn(entry)` gives the child its end of a two-way channel, a `Channel[Out, In]`, and the `Process[T, In, Out]` it returns holds the parent's end in its `channel` field. Use a process when the work should run on another core or must not take the parent down when it faults.

<!-- manuscript-example: test -->
```manuscript
import Channel from "@std/io/channels.ms"
import ProcessGroup from "@std/os/processes.ms"
import expect_equal, expect_ok from "@std/test/test.ms"

fn square_all(ch: Channel[Int, Int]) Int!:
    var c = ch
    var count = 0
    while true:
        if let n = try c.receive():
            try c.send(n * n)
            count += 1
        else:
            return ok(count)
    return ok(count)

test "a child process answers messages on its channel":
    let group = ProcessGroup[Int!, Int, Int]()
    var child = group.spawn(square_all) | try expect_ok
    child.channel.send(3) | try expect_ok
    child.channel.receive() | try expect_ok | try expect_equal(9)
    child.channel.close()
    child.result() | try expect_ok | try expect_ok | try expect_equal(1)
```

## How processes run

- `spawn(entry)` starts your executable again in a new process, at `entry` instead of `main`. No state is copied from the parent: the child starts fresh, and `entry` receives only its channel. It returns `Process[T, In, Out]!`; a child the host refuses to start is an `Error` of kind `Unavailable`, with the command runner's reason in `details["cause"]`.
- `entry` must name a top-level `fn`. A closure is rejected, because the values it captures cannot move to another process.
- `In`, `Out` and `T` cross as JSON, so they are copied. Use plain data: records, alternatives, lists, maps, strings and supported numbers. `Unit` works too. Transport uses ordinary `stringify`, not opt-in strict encoding; a type parameter alone does not guarantee a lossless JSON round trip. Check send, receive and result errors.
- The channel behaves as a task channel: `send` waits while the pipe is full, `receive` gives `ok(none)` once the other end closed and everything it sent was read, and `close` closes this end. A child that exits without closing its end gives an `Error` of kind `Closed`.
- `child.result()` waits for the entry to return and gives its value. Messages the parent has not received by then are dropped. A child that ended first gives an `Error` of kind `Failed` with the status in `details["status"]`: 67 after a fault, -1 after a signal. A fault in the child never faults the parent.
- `child.wait()` gives the exit status; `terminate()` and `kill()` signal the child's process group.
- A parent and child that each wait to receive from the other hang: the deadlock fault covers tasks and workers inside one process, and cannot see into another process. Close the channel from the side that finishes first.
- `group.results()` waits for every open child's result in start order, or gives the first error. Closing a process makes the group forget it and releases its descriptors once the `Process` value is dropped.
- Leaving the scope of the group binding closes every child: its channel closes, then the child is stopped and joined. Call `result()` first to keep the work.
- `stdin`, `stdout` and `stderr` default to the parent's own streams, so a child's output goes where the parent's goes. `Stdio.Null` discards a stream. `Stdio.Pipe` connects it to the parent: `child.stdin()` is a `WriteStream` (close it to end the child's input), and `child.stdout()` and `child.stderr()` are `ReadStream`s. Read a piped output while the child runs, since a child whose pipe is full waits. A stream that is not piped is already closed.

The child talks to the parent over its own pipe, not its standard streams: a socket pair on Linux and macOS and an owner-only named pipe on Windows. Waiting on it parks the task, as any I/O does.

Process-tree shutdown is platform-dependent. Group close requests termination and joins its child; it is not a portable guarantee that every descendant has exited.
