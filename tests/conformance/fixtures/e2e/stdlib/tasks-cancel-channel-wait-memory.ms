# conform: tags=with-cleanup,stdlib-tasks,tier-io
# conform: phase=run
from "@std/channels.ms" import Channel
from "@std/io.ms" import stdout
from "@std/process.ms" import control
from "@std/tasks.ms" import TaskError, TaskGroup
from "@std/testing.ms" import expect_equal, expect_error, expect_ok

# A task cancelled while parked in a channel receive must release the channel end it holds in a
# stack slot while it waits. Debug builds keep that value in the slot, so the unwind pass has to
# cover it: the heap must not grow across cancellations (#1513), and `make leak-check` finds no
# live block at exit.

def echo(ch: Channel[Int, Int]) -> Unit:
    var end = ch
    while True:
        let value = end.receive().get().get(-1)
        end.send(value).get()

def waiting(ready: Channel[Unit, Unit], ch: Channel[Int, Int]) -> Unit:
    var started = ready
    started.send(()).get()
    var end = ch
    let _ = end.receive()

def cancel_one(ch: Channel[Int, Int]) -> Result[Unit, Error]:
    with var group = TaskGroup[Unit]():
        let end = ch.clone()
        var task = group.spawn(lambda ready: waiting(ready, end.clone()))
        task.channel.receive() | try expect_ok | try expect_equal(some(()))
        group.close()
        task.result() | try expect_error | try expect_equal(TaskError.Closed)
    return ok(())

export def main() -> Int:
    with let owner = TaskGroup[Unit, Int, Int]():
        var task = owner.spawn(echo)
        for index in 0..4:
            cancel_one(task.channel.clone()).get()
            task.channel.send(0).get()
            task.channel.receive().get()
        let before = control().memory_usage().get()
        for index in 0..32:
            cancel_one(task.channel.clone()).get()
            task.channel.send(0).get()
            task.channel.receive().get()
        let after = control().memory_usage().get()
        stdout().write(f"growth {after.heap_used - before.heap_used}\n").get()
    return 0
