# conform: tags=closures,with-cleanup,stdlib-channels,stdlib-tasks,stdlib-workers,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
from "@std/channels.ms" import Channel, ChannelError
from "@std/tasks.ms" import Task, TaskGroup
from "@std/test.ms" import expect_equal, expect_true
from "@std/time.ms" import nanoseconds, sleep
from "@std/workers.ms" import Worker, WorkerGroup, worker_channel

# Edge behaviour found by probing the concurrency runtime: misuse and limits answer with errors, never a
# fault or a hang, and every wait here ends on its own.

def quick() -> Int:
    return 7

def slow() -> Int:
    sleep(nanoseconds(10000000000))
    return 1

def deaf(ch: Channel[Unit, Int]) -> Int:
    sleep(nanoseconds(10000000000))
    return 1

def mute(ch: Channel[Int, Unit]) -> Int:
    sleep(nanoseconds(10000000000))
    return 1

def waits() -> Unit:
    var ch = worker_channel[Int, Int]()
    let _got = ch.receive()

def waiter(t: Task[Int]) -> Int:
    let r = t.result()
    if r.is_ok():
        return 0
    return r.err().message().length()

def echo(ch: Channel[Int, Int]) -> Result[Int, ChannelError]:
    var c = ch
    var n = 0
    while True:
        if let v = try c.receive():
            try c.send(v + 1)
            n += 1
        else:
            return ok(n)
    return ok(n)

test "many tasks echo through their channels without losing a value":
    var total = 0
    var counts = 0
    with let group = TaskGroup[Result[Int, ChannelError], Int, Int]():
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
    # Each task echoes 0..199 plus one: 20 tasks, sum 19900 + 200 per task.
    try expect_equal(total, 20 * (19900 + 200))
    try expect_equal(counts, 20 * 200)

test "creating and closing task groups many times leaves them usable":
    var done = 0
    for i in 0..2000:
        with let group = TaskGroup[Int]():
            let t = group.spawn(lambda ch: quick())
            done += t.result().get(0)
    try expect_equal(done, 2000 * 7)

test "spawning into a closed group never runs the task":
    var group = TaskGroup[Int]()
    group.close()
    var t = group.spawn(lambda ch: quick())
    let r = t.result()
    try expect_equal(r.is_error(), True)
    try expect_equal(r.err().message(), "task: closed")
    try expect_equal(t.channel.send(()).is_ok(), False)

test "a zero timeout cancels the task instead of running it":
    with let group = TaskGroup[Int](timeout: some(nanoseconds(0))):
        let t = group.spawn(lambda ch: quick())
        try expect_equal(t.result().is_ok(), False)
    with let group = TaskGroup[Int]():
        let t = group.spawn(lambda ch: quick(), timeout: some(nanoseconds(0)))
        try expect_equal(t.result().is_ok(), False)

test "a task waiting on a task of another group sees it time out":
    var seen = 0
    with let a = TaskGroup[Int]():
        with let b = TaskGroup[Int](timeout: some(nanoseconds(50000000))):
            let tb = b.spawn(lambda ch: slow())
            let waiting = a.spawn(lambda ch: waiter(tb))
            seen = waiting.result().get(-1)
    try expect_equal(seen, "task: timed out".length())

test "a send to a task cancelled by its group ends with closed":
    with let group = TaskGroup[Int, Int, Unit](timeout: some(nanoseconds(100000000))):
        var t = group.spawn(deaf)
        var sent = 0
        var stopped = False
        while sent < 1000:
            let r = t.channel.send(sent)
            if r.is_error():
                stopped = True
                break
            sent += 1
        try expect_equal(stopped, True)

test "a receive from a task cancelled by its group ends with none":
    with let group = TaskGroup[Int, Unit, Int](timeout: some(nanoseconds(100000000))):
        var t = group.spawn(mute)
        let r = t.channel.receive()
        try expect_equal(r.is_ok(), True)
        try expect_equal(r.get().is_none(), True)

test "handles of a closed worker group answer instead of faulting":
    var kept: Optional[Worker[Int, Int]] = none
    with let group = WorkerGroup[Int, Int]():
        kept = some(group.spawn(waits).get())
    if let worker = kept:
        var w = worker
        try expect_equal(w.wait().is_ok(), False)
        try expect_equal(w.channel.send(1).is_ok(), False)
        w.cancel()

test "the worker limit refuses extra workers and frees slots when they end":
    with let group = WorkerGroup[Int, Int]():
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
        try expect_equal(again.is_ok(), True)
