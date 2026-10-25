# conform: tags=closures,with-cleanup,stdlib-channels,stdlib-workers,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
from "@std/channels.ms" import Channel, ChannelError
from "@std/collections.ms" import range
from "@std/core.ms" import panic
from "@std/io.ms" import stdin
from "@std/tasks.ms" import TaskGroup
from "@std/testing.ms" import expect_equal, expect_error, expect_ok, expect_true
from "@std/time.ms" import duration, sleep
from "@std/workers.ms" import WorkerError, WorkerGroup, worker_channel

type Job:
    id: Int
    words: List[String]

type Done:
    id: Int
    count: Int

def square_each(var ch: Channel[Int, Int]) -> Result[Unit, ChannelError]:
    while True:
        if let n = try ch.receive():
            try ch.send(n * n)
        else:
            return ok(())

    return ok(())

def squares() -> Unit:
    var ch = worker_channel[Int, Int]()
    let finished = square_each(var ch)

def count_words() -> Unit:
    var ch = worker_channel[Done, Job]()

    while True:
        let got = ch.receive()
        if got.is_error():
            return

        if let job = got.get(none):
            ch.send(Done(id: job.id, count: job.words.length()))
        else:
            return

def explode() -> Unit:
    var ch = worker_channel[Int, Int]()
    panic("worker boom")

def reads_stdin() -> Unit:
    var ch = worker_channel[Int, Int]()
    let input = stdin()

def naps() -> Unit:
    var ch = worker_channel[Int, Int]()
    sleep(duration(nanoseconds: 5000000))
    ch.send(1)

def wait_forever() -> Unit:
    var ch = worker_channel[Int, Int]()
    let got = ch.receive()

def announce_then_wait() -> Unit:
    var ch = worker_channel[Int, Int]()
    ch.send(1)
    let got = ch.receive()

# Runs without parking for long enough that the cancel always lands while it is computing.
def spin_then_wait() -> Unit:
    var ch = worker_channel[Int, Int]()
    ch.send(1)
    var n = 0
    for i in range(0, 300000000):
        n += i
    let got = ch.receive()

def sleep_long() -> Unit:
    sleep(duration(nanoseconds: 60000000000))

def sum_until_closed() -> Unit:
    var ch = worker_channel[Int, Int]()
    var total = 0

    while True:
        let got = ch.receive()
        if got.is_error():
            return

        if let n = got.get(none):
            total += n
        else:
            ch.send(total)
            return

def ask(group: WorkerGroup[Int, Int], value: Int) -> Result[Int, WorkerError]:
    var worker = try group.spawn(squares)
    worker.channel.send(value)

    var answer = -1
    if let got = worker.channel.receive().get(none):
        answer = got
    try worker.join()
    return ok(answer)

test "a worker answers a message":
    with WorkerGroup[Int, Int]() as group:
        try expect_equal(ask(group, 12), ok(144))

test "a worker answers each message in order":
    with WorkerGroup[Int, Int]() as group:
        var worker = group.spawn(squares).get(none)
        let sent = worker.channel.send(1)
        try expect_ok(sent)
        try expect_ok(worker.channel.send(2))
        try expect_ok(worker.channel.send(3))
        try expect_equal(worker.channel.receive(), ok(some(1)))
        try expect_equal(worker.channel.receive(), ok(some(4)))
        try expect_equal(worker.channel.receive(), ok(some(9)))
        worker.channel.close()
        try expect_ok(worker.join())

test "records cross as JSON":
    with WorkerGroup[Job, Done]() as group:
        var worker = group.spawn(count_words).get(none)
        try expect_ok(worker.channel.send(Job(id: 7, words: ["a", "b", "c"])))
        try expect_equal(worker.channel.receive(), ok(some(Done(id: 7, count: 3))))
        worker.channel.close()
        try expect_ok(worker.join())

test "many messages wait for room":
    with WorkerGroup[Int, Int]() as group:
        var worker = group.spawn(squares).get(none)
        var total = 0

        for n in range(0, 200):
            try expect_ok(worker.channel.send(n))
            if let got = worker.channel.receive().get(none):
                total += got

        worker.channel.close()
        try expect_ok(worker.join())
        try expect_equal(total, 2646700)

test "workers run side by side with memory of their own":
    with WorkerGroup[Int, Int]() as group:
        var first = group.spawn(sum_until_closed).get(none)
        var second = group.spawn(sum_until_closed).get(none)

        for n in range(0, 100):
            try expect_ok(first.channel.send(n))
            try expect_ok(second.channel.send(n * 2))

        first.channel.close()
        second.channel.close()
        try expect_ok(first.join())
        try expect_ok(second.join())

test "a fault in a worker is a result, not the end of the program":
    with WorkerGroup[Int, Int]() as group:
        var worker = group.spawn(explode).get(none)
        let outcome = worker.join()
        let ignored = try expect_error(outcome)

test "cancelling a worker stops it":
    with WorkerGroup[Int, Int]() as group:
        var worker = group.spawn(announce_then_wait).get(none)
        try expect_equal(worker.channel.receive(), ok(some(1)))
        worker.cancel()
        try expect_equal(worker.join(), error(WorkerError.Cancelled))

test "a worker cancelled while computing is cancelled at its next channel operation":
    with WorkerGroup[Int, Int]() as group:
        var worker = group.spawn(spin_then_wait).get(none)
        try expect_equal(worker.channel.receive(), ok(some(1)))
        worker.cancel()
        try expect_equal(worker.join(), error(WorkerError.Cancelled))

test "cancelling a worker right after spawn is not lost":
    with WorkerGroup[Int, Int]() as group:
        var worker = group.spawn(sleep_long).get(none)
        worker.cancel()
        try expect_equal(worker.join(), error(WorkerError.Cancelled))

test "leaving the group stops workers that are still running":
    with WorkerGroup[Int, Int]() as group:
        let worker = group.spawn(wait_forever)
        let ignored = try expect_ok(worker)

    try expect_equal(1, 1)

test "sends after the worker ended report the channel closed":
    with WorkerGroup[Int, Int]() as group:
        var worker = group.spawn(explode).get(none)
        let outcome = worker.join()
        let ignored = try expect_error(worker.channel.send(1))

test "a worker sleeps without blocking its starter":
    with WorkerGroup[Int, Int]() as group:
        var worker = group.spawn(naps).get(none)
        try expect_equal(worker.channel.receive(), ok(some(1)))
        try expect_ok(worker.join())

test "standard input stays with the main thread":
    with WorkerGroup[Int, Int]() as group:
        var worker = group.spawn(reads_stdin).get(none)
        let outcome = worker.join()
        let ignored = try expect_error(outcome)
        try expect_true(outcome.err().message().contains("main thread"))

def quick() -> Unit:
    var ch = worker_channel[Int, Int]()

test "cancelling a joined worker's handle leaves a later worker alone":
    with WorkerGroup[Int, Int]() as group:
        var a = group.spawn(quick).get(none)
        try expect_ok(a.join())
        var b = group.spawn(naps).get(none)
        a.cancel()
        try expect_equal(b.channel.receive(), ok(some(1)))
        try expect_ok(b.join())

def sends_one() -> Unit:
    var ch = worker_channel[Int, Int]()
    ch.send(1)

test "a finished worker's channel ends with none instead of an error":
    with WorkerGroup[Int, Int]() as group:
        var worker = group.spawn(sends_one).get(none)
        try expect_equal(worker.channel.receive(), ok(some(1)))
        try expect_equal(worker.channel.receive(), ok(none))
        try expect_ok(worker.join())

def runs_faulting_task() -> Unit:
    var ch = worker_channel[Int, Int]()
    with TaskGroup[Int]() as tasks:
        let t = tasks.spawn(lambda c: panic("task inside worker faults"))
        t.result()

test "a fault in a task a worker started is the worker's fault":
    with WorkerGroup[Int, Int]() as group:
        var worker = group.spawn(runs_faulting_task).get(none)
        let outcome = worker.join()
        let ignored = try expect_error(outcome)
        try expect_true(outcome.err().message().contains("task inside worker faults"))
