from "@std/channels.ms" import Channel
from "@std/process.ms" import control
from "@std/tasks.ms" import TaskError, TaskGroup
from "@std/test.ms" import expect_equal, expect_error, expect_ok

def hold_receive(ch: Channel[Int, Int]) -> Unit:
    var end = ch
    end.receive().get()

def hold_send(ch: Channel[Int, Int]) -> Unit:
    var end = ch
    for value in 0..17:
        end.send(value).get()

def echo_rounds(ch: Channel[Int, Int]) -> Unit:
    var end = ch

    while True:
        let value = end.receive().get().get(-1)
        end.send(value).get()

def drain_rounds(ch: Channel[Int, Int]) -> Unit:
    var end = ch

    while True:
        for value in 0..17:
            end.send(value).get()
        for value in 0..17:
            end.receive().get()

def receive_value(ready: Channel[Unit, Unit], target: Channel[Int, Int]) -> Int:
    var started = ready
    started.send(()).get()

    var end = target.clone()
    return end.receive().get().get(-1)

def send_value(ready: Channel[Unit, Unit], target: Channel[Int, Int]) -> Unit:
    var started = ready
    started.send(()).get()

    var end = target.clone()
    end.send(42).get()

def cancel_receive(target: Channel[Int, Int]) -> Result[Unit, Error]:
    var group = TaskGroup[Int]()
    let end = target.clone()
    var task = group.spawn(lambda ready: receive_value(ready, end))
    task.channel.receive() | try expect_ok | try expect_equal(some(()))

    # The acknowledging task parks on the target before this receive resumes us.
    group.close()
    task.result() | try expect_error | try expect_equal(TaskError.Closed)
    group.close()
    return ok(())

def cancel_send(target: Channel[Int, Int]) -> Result[Unit, Error]:
    var group = TaskGroup[Unit]()
    let end = target.clone()
    var task = group.spawn(lambda ready: send_value(ready, end))
    task.channel.receive() | try expect_ok | try expect_equal(some(()))
    group.close()
    task.result() | try expect_error | try expect_equal(TaskError.Closed)
    group.close()
    return ok(())

def wake_receiver(target: Channel[Int, Int]) -> Result[Unit, Error]:
    var end = target.clone()
    end.send(7) | try expect_ok
    end.receive() | try expect_ok | try expect_equal(some(7))
    return ok(())

def wake_sender(target: Channel[Int, Int]) -> Result[Unit, Error]:
    var end = target.clone()
    for value in 0..17:
        end.receive() | try expect_ok | try expect_equal(some(value))
    for value in 0..17:
        end.send(value) | try expect_ok
    return ok(())

# Both batches cancel identical tasks; waking only the control isolates waiter storage.
test "cancelled receives retain no more storage than the woken control":
    let owner = TaskGroup[Unit, Int, Int]()
    let task = owner.spawn(hold_receive)
    let comparison = TaskGroup[Unit, Int, Int]()
    let woken = comparison.spawn(echo_rounds)

    for index in 0..4:
        try cancel_receive(task.channel.clone())
        try cancel_receive(woken.channel.clone())
        try wake_receiver(woken.channel.clone())

    let before = control().memory_usage() | try expect_ok
    for index in 0..32:
        try cancel_receive(task.channel.clone())

    let retained = control().memory_usage() | try expect_ok

    for index in 0..32:
        try cancel_receive(woken.channel.clone())
        try wake_receiver(woken.channel.clone())

    let cleared = control().memory_usage() | try expect_ok
    (
        retained.heap_used - before.heap_used | try expect_equal(
            cleared.heap_used - retained.heap_used
        )
    )

test "cancelled sends retain no more storage than the woken control":
    let owner = TaskGroup[Unit, Int, Int]()
    var task = owner.spawn(hold_send)
    for value in 0..16:
        task.channel.send(value) | try expect_ok

    let comparison = TaskGroup[Unit, Int, Int]()
    var woken = comparison.spawn(drain_rounds)
    for value in 0..16:
        woken.channel.send(value) | try expect_ok

    for index in 0..4:
        try cancel_send(task.channel.clone())
        try cancel_send(woken.channel.clone())
        try wake_sender(woken.channel.clone())

    let before = control().memory_usage() | try expect_ok
    for index in 0..32:
        try cancel_send(task.channel.clone())

    let retained = control().memory_usage() | try expect_ok

    for index in 0..32:
        try cancel_send(woken.channel.clone())
        try wake_sender(woken.channel.clone())

    let cleared = control().memory_usage() | try expect_ok
    (
        retained.heap_used - before.heap_used | try expect_equal(
            cleared.heap_used - retained.heap_used
        )
    )

def echo_one(ch: Channel[Int, Int]) -> Unit:
    var end = ch
    let value = end.receive().get().get(-1)
    end.send(value).get()
    end.receive().get()

test "cancelling one receiver preserves another receivers wake":
    let owner = TaskGroup[Unit, Int, Int]()
    var target = owner.spawn(echo_one)
    let first_end = target.channel.clone()
    var cancelled = TaskGroup[Int]()
    var removed = cancelled.spawn(lambda ready: receive_value(ready, first_end))
    removed.channel.receive() | try expect_ok | try expect_equal(some(()))

    let survivor = TaskGroup[Int]()
    let second_end = target.channel.clone()
    var kept = survivor.spawn(lambda ready: receive_value(ready, second_end))
    kept.channel.receive() | try expect_ok | try expect_equal(some(()))
    cancelled.close()
    target.channel.send(7) | try expect_ok
    kept.result() | try expect_ok | try expect_equal(7)
