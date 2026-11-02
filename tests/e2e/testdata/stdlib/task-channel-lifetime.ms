import Channel from "@std/io/channels.ms"
import memory_usage from "@std/os/process.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal, expect_error, expect_ok, expect_true from "@std/test/test.ms"
import nanoseconds, sleep from "@std/os/time.ms"

fn send_one(ch: Channel[Int, Unit]) Unit!:
    try ch.send(7)
    return ok(unit)

fn send_nothing(ch: Channel[Int, Unit]) Unit!:
    return ok(unit)

fn retained_end(group: TaskGroup[Unit!, Unit, Int]) Channel[Unit, Int]!:
    let task = group.spawn(send_one)
    task.result() | try expect_ok | try expect_ok
    return ok(task.channel.clone())

fn send_payloads(ch: Channel[String, Unit]) Unit!:
    var end = ch
    for index in 0..16:
        try end.send("unread channel payload".repeat(16).get(""))
    return ok(unit)

fn collect_and_drop(group: TaskGroup[Unit!, Unit, Int]) Unit!:
    let task = group.spawn(send_one)
    task.result() | try expect_ok | try expect_ok
    return ok(unit)

fn close_on_return() Channel[Unit, Int]!:
    let group = TaskGroup[Unit!, Unit, Int]()
    let task = group.spawn(send_one)
    task.result() | try expect_ok | try expect_ok
    return ok(task.channel.clone())

fn close_on_cancel(ch: Channel[Channel[Unit, Int], Unit]) Unit:
    let group = TaskGroup[Unit!, Unit, Int]()
    let task = group.spawn(send_one)
    let _sent = task.result()
    var end = ch
    let _ = end.send(task.channel.clone())
    sleep(nanoseconds(1000000000))

test "collected buffered channels close with their group":
    var group = TaskGroup[Unit!, Unit, Int]()
    var task = group.spawn(send_one)
    task.result() | try expect_ok | try expect_ok
    try group.close()
    task.channel.receive() | try expect_error | try expect_equal(
        Error("channel: closed", kind: ErrorCategory.Closed)
    )
    task.channel.send(
        unit
    ) | try expect_error | try expect_equal(
        Error("channel: closed", kind: ErrorCategory.Closed)
    )

test "collected empty channels close with their group":
    var group = TaskGroup[Unit!, Unit, Int]()
    var task = group.spawn(send_nothing)
    task.result() | try expect_ok | try expect_ok
    try group.close()
    task.channel.receive() | try expect_error | try expect_equal(
        Error("channel: closed", kind: ErrorCategory.Closed)
    )

test "results collection preserves group ownership of cloned channels":
    var group = TaskGroup[Unit!, Unit, Int]()
    let task = group.spawn(send_one)
    var end = task.channel.clone()
    let results = group.results() | try expect_ok
    results.length() | try expect_equal(1)
    results[0] | try expect_ok
    try group.close()
    end.receive() | try expect_error | try expect_equal(
        Error("channel: closed", kind: ErrorCategory.Closed)
    )

test "a channel retained without its collected task closes with the group":
    var group = TaskGroup[Unit!, Unit, Int]()
    var end = retained_end(group) | try expect_ok
    try group.close()
    end.receive() | try expect_error | try expect_equal(
        Error("channel: closed", kind: ErrorCategory.Closed)
    )

test "collected channels can drain buffered values before group close":
    var group = TaskGroup[Unit!, Unit, Int]()
    var task = group.spawn(send_one)
    task.result() | try expect_ok | try expect_ok
    task.channel.receive() | try expect_ok | try expect_equal(7)
    task.channel.receive() | try expect_ok | try expect_equal(none)
    try group.close()
    task.channel.receive() | try expect_error | try expect_equal(
        Error("channel: closed", kind: ErrorCategory.Closed)
    )

test "uncollected channels still close with their group":
    var group = TaskGroup[Unit!, Unit, Int]()
    var task = group.spawn(send_one)
    group.wait() | try expect_ok
    try group.close()
    task.channel.receive() | try expect_error | try expect_equal(
        Error("channel: closed", kind: ErrorCategory.Closed)
    )

test "repeated close cannot close another groups channels":
    var first = TaskGroup[Unit!, Unit, Int]()
    var old = first.spawn(send_one)
    old.result() | try expect_ok | try expect_ok
    try first.close()

    let second = TaskGroup[Unit!, Unit, Int]()
    var fresh = second.spawn(send_one)
    fresh.result() | try expect_ok | try expect_ok
    try first.close()
    old.channel.receive() | try expect_error | try expect_equal(
        Error("channel: closed", kind: ErrorCategory.Closed)
    )
    fresh.channel.receive() | try expect_ok | try expect_equal(7)

test "group close releases unread payloads while the channel stays alive":
    var group = TaskGroup[Unit!, Unit, String]()
    var task = group.spawn(send_payloads)
    task.result() | try expect_ok | try expect_ok

    let before = memory_usage() | try expect_ok
    try group.close()

    let after = memory_usage() | try expect_ok
    try expect_true(before.heap_used - after.heap_used >= 16 * 352)
    task.channel.receive() | try expect_error | try expect_equal(
        Error("channel: closed", kind: ErrorCategory.Closed)
    )

test "a long lived group does not retain discarded collected channels":
    let group = TaskGroup[Unit!, Unit, Int]()
    for index in 0..128:
        try collect_and_drop(group)

    let before = memory_usage() | try expect_ok
    for index in 0..2000:
        try collect_and_drop(group)

    let after = memory_usage() | try expect_ok
    try expect_true(after.heap_used <= before.heap_used + 1024)
    group.tasks.get().length() | try expect_equal(0)

test "channels spawned after group close are closed immediately":
    var group = TaskGroup[Unit!, Unit, Int]()
    try group.close()

    var late = group.spawn(send_one)
    late.result() | try expect_error | try expect_equal(
        Error("task: closed", kind: ErrorCategory.Closed)
    )
    late.channel.receive() | try expect_error | try expect_equal(
        Error("channel: closed", kind: ErrorCategory.Closed)
    )
    try group.close()

test "return cleanup closes a collected channels retained end":
    var end = close_on_return() | try expect_ok
    end.receive() | try expect_error | try expect_equal(
        Error("channel: closed", kind: ErrorCategory.Closed)
    )

test "cancellation cleanup closes collected channels retained outside the task":
    let outer = TaskGroup[Unit, Unit, Channel[Unit, Int]]()
    var task = outer.spawn(close_on_cancel, timeout: nanoseconds(20000000))

    if var end = task.channel.receive() | try expect_ok:
        task.result() | try expect_error | try expect_equal(
            Error("task: timed out", kind: ErrorCategory.Timeout)
        )
        end.receive() | try expect_error | try expect_equal(
            Error("channel: closed", kind: ErrorCategory.Closed)
        )
    else:
        try expect_true(false)

fn double_all(ch: Channel[Int, Int]) Int:
    var count = 0

    while true:
        let received = ch.receive().get(none)
        if received.is_none():
            return count

        ch.send(received.get(0) * 2).get()
        count += 1

    return count

test "channel ends send and receive without a var binding":
    let group = TaskGroup[Int, Int, Int]()
    let task = group.spawn(double_all)
    task.channel.send(4) | try expect_ok
    task.channel.receive() | try expect_ok | try expect_equal(8)
