# conform: tags=closures,scope-cleanup,stdlib-channels,stdlib-tasks,stdlib-workers,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
import Channel, ChannelError from "@std/io/channels.ms"
import Task, TaskGroup from "@std/concurrency/tasks.ms"
import expect_equal, expect_true from "@std/test/test.ms"
import nanoseconds, sleep from "@std/os/time.ms"
import Worker, WorkerGroup, worker_channel from "@std/concurrency/workers.ms"

# Edge behaviour found by probing the concurrency runtime: misuse and limits answer with errors, never a
# fault or a hang, and every wait here ends on its own.

fn quick() Int:
    return 7

fn slow() Int:
    sleep(nanoseconds(10000000000))
    return 1

fn deaf(var ch: Channel[Unit, Int]) Int:
    sleep(nanoseconds(10000000000))
    return 1

fn mute(var ch: Channel[Int, Unit]) Int:
    sleep(nanoseconds(10000000000))
    return 1

fn waits() Unit:
    var ch = worker_channel[Int, Int]()
    let _got = ch.receive()

# The task owns its copy of `t`, which shares the waited task's state.
fn waiter(t: Task[Int]) Int:
    var mine = t.clone()
    let r = mine.result()
    if r.is_ok():
        return 0

    return r.err().message().length()

fn echo(var ch: Channel[Int, Int]) Int!ChannelError:
    var n = 0

    while true:
        if let v = try ch.receive():
            try ch.send(v + 1)
            n += 1
        else:
            return ok(n)

    return ok(n)

test "many tasks echo through their channels without losing a value":
    var total = 0
    var counts = 0
    var group = TaskGroup[Int!ChannelError, Int, Int]()

    for t in 0..20:
        var task = group.spawn(echo)

        for i in 0..200:
            task.channel.send(i).get()
            if i % 8 == 7:
                for k in 0..8:
                    total += task.channel.receive().get().get(0)

        task.channel.close()

    let results = group.results().get()
    for r in results:
        counts += r.get(0)
    try group.close()

    # Each task echoes 0..199 plus one: 20 tasks, sum 19900 + 200 per task.
    try expect_equal(total, 20 * (19900 + 200))
    try expect_equal(counts, 20 * 200)

test "creating and closing task groups many times leaves them usable":
    var done = 0

    for i in 0..2000:
        var group = TaskGroup[Int]()
        var t = group.spawn(fn var ch: quick())
        done += t.result().get(0)

    try expect_equal(done, 2000 * 7)

test "spawning into a closed group never runs the task":
    var group = TaskGroup[Int]()
    try group.close()

    var t = group.spawn(fn var ch: quick())
    let r = t.result()
    try expect_equal(r.is_error(), true)
    try expect_equal(r.err().message(), "task: closed")
    try expect_equal(t.channel.send(unit).is_ok(), false)

test "a zero timeout cancels the task instead of running it":
    var group = TaskGroup[Int](timeout: nanoseconds(0))
    var t = group.spawn(fn var ch: quick())
    try expect_equal(t.result().is_ok(), false)
    try group.close()

    var group2 = TaskGroup[Int]()
    var t2 = group2.spawn(fn var ch: quick(), timeout: nanoseconds(0))
    try expect_equal(t2.result().is_ok(), false)

test "a task waiting on a task of another group sees it time out":
    var seen = 0
    var a = TaskGroup[Int]()
    var b = TaskGroup[Int](timeout: nanoseconds(50000000))
    let tb = b.spawn(fn var ch: slow())
    var waiting = a.spawn(fn var ch: waiter(tb))
    seen = waiting.result().get(-1)
    try a.close()
    try expect_equal(seen, "task: timed out".length())

test "a send to a task cancelled by its group ends with closed":
    var group = TaskGroup[Int, Int, Unit](timeout: nanoseconds(100000000))
    var t = group.spawn(deaf)
    var sent = 0
    var stopped = false

    while sent < 1000:
        let r = t.channel.send(sent)

        if r.is_error():
            stopped = true
            break

        sent += 1

    try expect_equal(stopped, true)

test "a receive from a task cancelled by its group ends with none":
    var group = TaskGroup[Int, Unit, Int](timeout: nanoseconds(100000000))
    var t = group.spawn(mute)
    let r = t.channel.receive()
    try expect_equal(r.is_ok(), true)
    try expect_equal(r.get().is_none(), true)

test "handles of a closed worker group answer instead of faulting":
    var kept: Worker[Int, Int]? = none
    var group = WorkerGroup[Int, Int]()
    kept = group.spawn(waits).get()
    try group.close()

    if let worker = kept:
        var w = worker
        try expect_equal(w.wait().is_ok(), false)
        try expect_equal(w.channel.send(1).is_ok(), false)
        w.cancel()

test "the worker limit refuses extra workers and frees slots when they end":
    var group = WorkerGroup[Int, Int]()
    var started = List[Worker[Int, Int]]()
    var refused = 0

    for i in 0..300:
        let w = group.spawn(waits)

        if w.is_ok():
            started.append(w.get().clone())
        else:
            refused += 1

    try expect_true(refused > 0)
    try expect_equal(started.length() + refused, 300)
    for i in 0..started.length():
        started[i].cancel()
    for i in 0..started.length():
        let _ended = started[i].wait()

    let again = group.spawn(waits)
    try expect_equal(again.is_ok(), true)
