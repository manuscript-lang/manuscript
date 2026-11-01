# conform: tags=scope-cleanup,stdlib-tasks,tier-io
# conform: phase=run
import Channel from "@std/io/channels.ms"
import stdout from "@std/io/io.ms"
import memory_usage from "@std/os/process.ms"
import TaskError, TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal, expect_error, expect_ok from "@std/test/test.ms"

# A task cancelled while parked in a channel receive must release the channel end it holds in a
# stack slot while it waits. Debug builds keep that value in the slot, so the unwind pass has to
# cover it: the heap must not grow across cancellations (#1513), and `make leak-check` finds no
# live block at exit.

fn echo(var ch: Channel[Int, Int]) Unit:
    while true:
        let value = ch.receive().get().get(-1)
        ch.send(value).get()

fn waiting(ready: Channel[Unit, Unit], ch: Channel[Int, Int]) Unit:
    var started = ready
    started.send(unit).get()

    var end = ch
    let _ignored = end.receive()

fn cancel_one(ch: Channel[Int, Int]) Unit!:
    var group = TaskGroup[Unit]()
    let end = ch.clone()
    var task = group.spawn(fn var ready: waiting(ready, end.clone()))
    task.channel.receive() | try expect_ok | try expect_equal(unit)
    try group.close()
    task.result() | try expect_error | try expect_equal(TaskError.Closed)
    try group.close()
    return ok(unit)

export fn main() Int:
    var owner = TaskGroup[Unit, Int, Int]()
    var task = owner.spawn(echo)

    for index in 0..4:
        cancel_one(task.channel.clone()).get()
        task.channel.send(0).get()
        task.channel.receive().get()

    let before = memory_usage().get()

    for index in 0..32:
        cancel_one(task.channel.clone()).get()
        task.channel.send(0).get()
        task.channel.receive().get()

    let after = memory_usage().get()
    stdout().write("growth {after.heap_used - before.heap_used}\n").get()
    owner.close().get(none)
    return 0
