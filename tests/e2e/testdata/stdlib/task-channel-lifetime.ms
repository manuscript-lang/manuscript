import Channel, ChannelError from "@std/io/channels.ms"
import memory_usage from "@std/os/process.ms"
import TaskError, TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal, expect_error, expect_ok, expect_true from "@std/test/test.ms"
import nanoseconds, sleep from "@std/os/time.ms"

fn send_one(var ch: Channel[Int, Unit]) Unit!ChannelError:
    try ch.send(7)
    return ok(unit)

fn send_nothing(var ch: Channel[Int, Unit]) Unit!ChannelError:
    return ok(unit)

fn retained_end(var group: TaskGroup[Unit!ChannelError, Unit, Int]) Channel[Unit, Int]!:
    var task = group.spawn(send_one)
    task.result() | try expect_ok | try expect_ok
    return ok(task.channel.clone())

fn send_payloads(var ch: Channel[String, Unit]) Unit!ChannelError:
    for index in 0..16:
        try ch.send("unread channel payload".repeat(16).get(""))
    return ok(unit)

fn collect_and_drop(var group: TaskGroup[Unit!ChannelError, Unit, Int]) Unit!:
    var task = group.spawn(send_one)
    task.result() | try expect_ok | try expect_ok
    return ok(unit)

fn close_on_return() Channel[Unit, Int]!:
    var group = TaskGroup[Unit!ChannelError, Unit, Int]()
    var task = group.spawn(send_one)
    task.result() | try expect_ok | try expect_ok
    return ok(task.channel.clone())

fn close_on_cancel(var ch: Channel[Channel[Unit, Int], Unit]) Unit:
    var group = TaskGroup[Unit!ChannelError, Unit, Int]()
    var task = group.spawn(send_one)
    let _sent = task.result()
    let _ = ch.send(task.channel.clone())
    sleep(nanoseconds(1000000000))

test "collected buffered channels close with their group":
    var group = TaskGroup[Unit!ChannelError, Unit, Int]()
    var task = group.spawn(send_one)
    task.result() | try expect_ok | try expect_ok
    try group.close()
    task.channel.receive() | try expect_error | try expect_equal(ChannelError.Closed)
    task.channel.send(unit) | try expect_error | try expect_equal(ChannelError.Closed)

test "collected empty channels close with their group":
    var group = TaskGroup[Unit!ChannelError, Unit, Int]()
    var task = group.spawn(send_nothing)
    task.result() | try expect_ok | try expect_ok
    try group.close()
    task.channel.receive() | try expect_error | try expect_equal(ChannelError.Closed)

test "results collection preserves group ownership of cloned channels":
    var group = TaskGroup[Unit!ChannelError, Unit, Int]()
    var task = group.spawn(send_one)
    var end = task.channel.clone()
    let results = group.results() | try expect_ok
    results.length() | try expect_equal(1)
    results[0] | try expect_ok
    try group.close()
    end.receive() | try expect_error | try expect_equal(ChannelError.Closed)

test "a channel retained without its collected task closes with the group":
    var group = TaskGroup[Unit!ChannelError, Unit, Int]()
    var end = retained_end(var group) | try expect_ok
    try group.close()
    end.receive() | try expect_error | try expect_equal(ChannelError.Closed)

test "collected channels can drain buffered values before group close":
    var group = TaskGroup[Unit!ChannelError, Unit, Int]()
    var task = group.spawn(send_one)
    task.result() | try expect_ok | try expect_ok
    task.channel.receive() | try expect_ok | try expect_equal(7)
    task.channel.receive() | try expect_ok | try expect_equal(none)
    try group.close()
    task.channel.receive() | try expect_error | try expect_equal(ChannelError.Closed)

test "uncollected channels still close with their group":
    var group = TaskGroup[Unit!ChannelError, Unit, Int]()
    var task = group.spawn(send_one)
    group.wait() | try expect_ok
    try group.close()
    task.channel.receive() | try expect_error | try expect_equal(ChannelError.Closed)

test "repeated close cannot close another groups channels":
    var first = TaskGroup[Unit!ChannelError, Unit, Int]()
    var old = first.spawn(send_one)
    old.result() | try expect_ok | try expect_ok
    try first.close()

    var second = TaskGroup[Unit!ChannelError, Unit, Int]()
    var fresh = second.spawn(send_one)
    fresh.result() | try expect_ok | try expect_ok
    try first.close()
    old.channel.receive() | try expect_error | try expect_equal(ChannelError.Closed)
    fresh.channel.receive() | try expect_ok | try expect_equal(7)

test "group close releases unread payloads while the channel stays alive":
    var group = TaskGroup[Unit!ChannelError, Unit, String]()
    var task = group.spawn(send_payloads)
    task.result() | try expect_ok | try expect_ok

    let before = memory_usage() | try expect_ok
    try group.close()

    let after = memory_usage() | try expect_ok
    try expect_true(before.heap_used - after.heap_used >= 16 * 352)
    task.channel.receive() | try expect_error | try expect_equal(ChannelError.Closed)

test "a long lived group does not retain discarded collected channels":
    var group = TaskGroup[Unit!ChannelError, Unit, Int]()
    for index in 0..128:
        try collect_and_drop(var group)

    let before = memory_usage() | try expect_ok
    for index in 0..2000:
        try collect_and_drop(var group)

    let after = memory_usage() | try expect_ok
    try expect_true(after.heap_used <= before.heap_used + 1024)
    group.tasks.length() | try expect_equal(0)

test "channels spawned after group close are closed immediately":
    var group = TaskGroup[Unit!ChannelError, Unit, Int]()
    try group.close()

    var late = group.spawn(send_one)
    late.result() | try expect_error | try expect_equal(TaskError.Closed)
    late.channel.receive() | try expect_error | try expect_equal(ChannelError.Closed)
    try group.close()

test "return cleanup closes a collected channels retained end":
    var end = close_on_return() | try expect_ok
    end.receive() | try expect_error | try expect_equal(ChannelError.Closed)

test "cancellation cleanup closes collected channels retained outside the task":
    var outer = TaskGroup[Unit, Unit, Channel[Unit, Int]]()
    var task = outer.spawn(close_on_cancel, timeout: nanoseconds(20000000))

    if var end = task.channel.receive() | try expect_ok:
        task.result() | try expect_error | try expect_equal(TaskError.TimedOut)
        end.receive() | try expect_error | try expect_equal(ChannelError.Closed)
    else:
        try expect_true(false)

fn double_all(var ch: Channel[Int, Int]) Int:
    var count = 0

    while true:
        let received = ch.receive().get(none)
        if received.is_none():
            return count

        ch.send(received.get(0) * 2).get()
        count += 1

    return count

test "channel ends send and receive without a var binding":
    var group = TaskGroup[Int, Int, Int]()
    var task = group.spawn(double_all)
    task.channel.send(4) | try expect_ok
    task.channel.receive() | try expect_ok | try expect_equal(8)
