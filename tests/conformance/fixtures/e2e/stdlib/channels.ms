# conform: tags=closures,scope-cleanup,stdlib-channels,stdlib-tasks,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
import {Channel, ChannelError} from "@std/channels.ms"
import {TaskError, TaskGroup} from "@std/tasks.ms"
import {expect_equal, expect_error, expect_ok} from "@std/test.ms"
import {nanoseconds, sleep} from "@std/time.ms"

fn square_all(ch: Channel[Int, Int]) Result[Int, ChannelError]:
    var c = ch
    var count = 0

    while true:
        if let n = try c.receive():
            try c.send(n * n)
            count += 1
        else:
            return ok(count)

    return ok(count)

fn produce(ch: Channel[Int, Unit]) Int:
    var c = ch
    for n in 0..40:
        if c.send(n).is_error():
            return -1
    return 40

fn wait_for_one(ch: Channel[Int, Unit]) Int:
    var c = ch
    if let _got = c.receive():
        return 1

    return 2

fn send_all(ch: Channel[Int, Unit], base: Int) Int:
    var c = ch
    for n in 0..50:
        if c.send(base + n).is_error():
            return -1
    return 50

fn total(ch: Channel[Unit, Int]) Int:
    var c = ch
    var sum = 0

    while true:
        let got = c.receive()
        if got.is_error():
            return sum

        if let value = got.get():
            sum += value
        else:
            return sum

    return sum

# Reads every value until the channel ends: the values, then how it ended.
fn drain(var ch: Channel[Unit, Int]) List[String]:
    var seen = List[String]()

    while true:
        let got = ch.receive()

        if got.is_error():
            seen.append("closed")
            return seen

        if let value = got.get():
            seen.append("{value}")
        else:
            seen.append("end")
            return seen

    return seen

test "a task answers each message in order":
    let group = TaskGroup[Result[Int, ChannelError], Int, Int]()
    var task = group.spawn(square_all)
    var replies = List[Int]()

    for n in 1..41:
        task.channel.send(n) | try expect_ok
        if n % 4 == 0:
            for k in 0..4:
                if let reply = task.channel.receive() | try expect_ok:
                    replies.append(reply)

    task.channel.close()
    try expect_equal(replies.length(), 40)
    try expect_equal(replies.get(0), 1)
    try expect_equal(replies.get(39), 1600)

    let answered = task.result() | try expect_ok
    answered | try expect_ok | try expect_equal(40)

test "the group reads what a finished task sent, then the end":
    let group = TaskGroup[Int, Unit, Int]()
    var task = group.spawn(produce)
    let seen = drain(var task.channel)
    try expect_equal(seen.length(), 41)
    try expect_equal(seen.get(39), "39")
    try expect_equal(seen.get(40), "end")
    task.result() | try expect_ok | try expect_equal(40)

test "sending after the other end closed gives Closed":
    let group = TaskGroup[Int, Int, Unit]()
    var task = group.spawn(fn ch: 0)
    task.result() | try expect_ok | try expect_equal(0)
    task.channel.send(1) | try expect_error | try expect_equal(ChannelError.Closed)

test "an end used after closing it gives Closed":
    let group = TaskGroup[Result[Int, ChannelError], Int, Int]()
    var task = group.spawn(square_all)
    task.channel.close()
    task.channel.send(1) | try expect_error | try expect_equal(ChannelError.Closed)
    task.channel.receive() | try expect_error | try expect_equal(ChannelError.Closed)
    task.channel.close()

test "a task cancelled while it waits closes its end":
    let group = TaskGroup[Int, Unit, Int](timeout: some(nanoseconds(20000000)))
    var task = group.spawn(wait_for_one)
    try expect_equal(drain(var task.channel), ["end"])
    task.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "a task cancelled before it first ran closes its end":
    let group = TaskGroup[Int, Unit, Int]()
    var task = group.spawn(produce, timeout: some(nanoseconds(0)))
    try expect_equal(drain(var task.channel), ["end"])
    task.result() | try expect_error | try expect_equal(TaskError.TimedOut)

test "closing the group closes every channel":
    var group = TaskGroup[Int, Unit, Int]()
    var task = group.spawn(produce)
    group.close()
    try expect_equal(drain(var task.channel), ["closed"])

    var late = group.spawn(produce)
    try expect_equal(drain(var late.channel), ["closed"])

test "a group without channel types gives each task a Unit channel":
    let group = TaskGroup[Int]()
    var task = group.spawn(fn ch: 3)
    task.result() | try expect_ok | try expect_equal(3)
    task.channel.receive() | try expect_ok | try expect_equal(none)

test "cloned ends share one channel":
    let group = TaskGroup[Int, Int, Unit]()
    var sink = group.spawn(total)
    let first = sink.channel.clone()
    let second = sink.channel.clone()
    let a = group.spawn(fn ch: send_all(first.clone(), 0))
    let b = group.spawn(fn ch: send_all(second.clone(), 100))
    a.result() | try expect_ok | try expect_equal(50)
    b.result() | try expect_ok | try expect_equal(50)
    sink.channel.close()
    sink.result() | try expect_ok | try expect_equal(7450)

test "channel errors describe themselves":
    try expect_equal(ChannelError.Closed.message(), "channel: closed")
    try expect_equal(
        ChannelError.Broken("peer exited").message(), "channel: broken: peer exited"
    )
