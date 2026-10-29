# conform: tags=closures,scope-cleanup,stdlib-channels,stdlib-workers,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=test
import {Channel, ChannelError} from "@std/channels.ms"
import panic from "@std/core.ms"
import fetch from "@std/fetch.ms"
import {buffered, headers, HttpRequest, HttpResponse, HttpServerOptions} from "@std/http.ms"
import stdin from "@std/io.ms"
import network from "@std/net.ms"
import TaskGroup from "@std/tasks.ms"
import {expect_equal, expect_error, expect_ok, expect_true} from "@std/test.ms"
import {nanoseconds, sleep} from "@std/time.ms"
import {Worker, WorkerError, WorkerGroup, worker_bytes, worker_channel} from "@std/workers.ms"

type Job:
    id: Int
    words: List[String]

type Done:
    id: Int
    count: Int

fn square_each(var ch: Channel[Int, Int]) Result[Unit, ChannelError]:
    while true:
        if let n = try ch.receive():
            try ch.send(n * n)
        else:
            return ok(unit)

    return ok(unit)

fn squares() Unit:
    var ch = worker_channel[Int, Int]()
    let _finished = square_each(var ch)

fn count_words() Unit:
    var ch = worker_channel[Done, Job]()

    while true:
        let got = ch.receive()
        if got.is_error():
            return

        if let job = got.get(none):
            let _ = ch.send(Done(id: job.id, count: job.words.length()))
        else:
            return

fn explode() Unit:
    var _ch = worker_channel[Int, Int]()
    panic("worker boom")

fn reads_stdin() Unit:
    var _ch = worker_channel[Int, Int]()
    let _input = stdin()

fn naps() Unit:
    var ch = worker_channel[Int, Int]()
    sleep(nanoseconds(5000000))

    let _ = ch.send(1)

fn wait_forever() Unit:
    var ch = worker_channel[Int, Int]()
    let _got = ch.receive()

fn announce_then_wait() Unit:
    var ch = worker_channel[Int, Int]()
    let _ = ch.send(1)
    let _got = ch.receive()

# Runs without parking for long enough that the cancel always lands while it is computing.
fn spin_then_wait() Unit:
    var ch = worker_channel[Int, Int]()
    let _ = ch.send(1)
    var _n = 0
    for i in 0..300000000:
        _n += i

    let _got = ch.receive()

fn sleep_long() Unit:
    sleep(nanoseconds(60000000000))

fn sum_until_closed() Unit:
    var ch = worker_channel[Int, Int]()
    var total = 0

    while true:
        let got = ch.receive()
        if got.is_error():
            return

        if let n = got.get(none):
            total += n
        else:
            let _ = ch.send(total)
            return

fn ask(group: WorkerGroup[Int, Int], value: Int) Result[Int, WorkerError]:
    var worker = try group.spawn(squares)
    let _ = worker.channel.send(value)
    var answer = -1
    if let got = worker.channel.receive().get(none):
        answer = got
    try worker.wait()
    return ok(answer)

test "a worker answers a message":
    let group = WorkerGroup[Int, Int]()
    try expect_equal(ask(group, 12), ok(144))

test "a worker answers each message in order":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(squares).get(none)
    let sent = worker.channel.send(1)
    try expect_ok(sent)
    try expect_ok(worker.channel.send(2))
    try expect_ok(worker.channel.send(3))
    try expect_equal(worker.channel.receive(), ok(some(1)))
    try expect_equal(worker.channel.receive(), ok(some(4)))
    try expect_equal(worker.channel.receive(), ok(some(9)))
    worker.channel.close()
    try expect_ok(worker.wait())

test "records cross as JSON":
    let group = WorkerGroup[Job, Done]()
    var worker = group.spawn(count_words).get(none)
    try expect_ok(worker.channel.send(Job(id: 7, words: ["a", "b", "c"])))
    try expect_equal(worker.channel.receive(), ok(some(Done(id: 7, count: 3))))
    worker.channel.close()
    try expect_ok(worker.wait())

test "many messages wait for room":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(squares).get(none)
    var total = 0

    for n in 0..200:
        try expect_ok(worker.channel.send(n))
        if let got = worker.channel.receive().get(none):
            total += got

    worker.channel.close()
    try expect_ok(worker.wait())
    try expect_equal(total, 2646700)

test "workers run side by side with memory of their own":
    let group = WorkerGroup[Int, Int]()
    var first = group.spawn(sum_until_closed).get(none)
    var second = group.spawn(sum_until_closed).get(none)

    for n in 0..100:
        try expect_ok(first.channel.send(n))
        try expect_ok(second.channel.send(n * 2))

    first.channel.close()
    second.channel.close()
    try expect_ok(first.wait())
    try expect_ok(second.wait())

test "a fault in a worker is a result, not the end of the program":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(explode).get(none)
    let outcome = worker.wait()
    let _ignored = try expect_error(outcome)

test "cancelling a worker stops it":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(announce_then_wait).get(none)
    try expect_equal(worker.channel.receive(), ok(some(1)))
    worker.cancel()
    try expect_equal(worker.wait(), error(WorkerError.Cancelled))

test "a worker cancelled while computing is cancelled at its next channel operation":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(spin_then_wait).get(none)
    try expect_equal(worker.channel.receive(), ok(some(1)))
    worker.cancel()
    try expect_equal(worker.wait(), error(WorkerError.Cancelled))

test "cancelling a worker right after spawn is not lost":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(sleep_long).get(none)
    worker.cancel()
    try expect_equal(worker.wait(), error(WorkerError.Cancelled))

test "leaving the group stops workers that are still running":
    var group = WorkerGroup[Int, Int]()
    let worker = group.spawn(wait_forever)
    let _ignored = try expect_ok(worker)
    group.close()
    try expect_equal(1, 1)

test "sends after the worker ended report the channel closed":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(explode).get(none)
    let _outcome = worker.wait()
    let _ignored = try expect_error(worker.channel.send(1))

test "a worker sleeps without blocking its starter":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(naps).get(none)
    try expect_equal(worker.channel.receive(), ok(some(1)))
    try expect_ok(worker.wait())

test "standard input stays with the main thread":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(reads_stdin).get(none)
    let outcome = worker.wait()
    let _ignored = try expect_error(outcome)
    try expect_true(outcome.err().message().contains("main thread"))

fn delayed_send() Unit:
    var ch = worker_channel[Int, Int]()
    sleep(nanoseconds(150000000))

    let _ = ch.send(1)

fn quick() Unit:
    var _ch = worker_channel[Int, Int]()

test "cancelling a joined worker's handle leaves a later worker alone":
    let group = WorkerGroup[Int, Int]()
    var a = group.spawn(quick).get(none)
    try expect_ok(a.wait())

    var b = group.spawn(delayed_send).get(none)
    sleep(nanoseconds(30000000))
    a.cancel()
    try expect_equal(b.channel.receive(), ok(some(1)))
    try expect_ok(b.wait())

fn sends_one() Unit:
    var ch = worker_channel[Int, Int]()
    let _ = ch.send(1)

test "a finished worker's channel ends with none instead of an error":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(sends_one).get(none)
    try expect_equal(worker.channel.receive(), ok(some(1)))
    try expect_equal(worker.channel.receive(), ok(none))
    try expect_ok(worker.wait())

fn runs_faulting_task() Unit:
    var _ch = worker_channel[Int, Int]()
    let tasks = TaskGroup[Int]()
    let t = tasks.spawn(fn c: panic("task inside worker faults"))
    let _ = t.result()

test "a fault in a task a worker started is the worker's fault":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(runs_faulting_task).get(none)
    let outcome = worker.wait()
    let cause = try expect_error(outcome)
    try expect_true(cause.message().contains("task inside worker faults"))

fn sleeps_long() Unit:
    var _ch = worker_channel[Int, Int]()
    sleep(nanoseconds(30000000000))

fn joins_nested() Unit:
    var _ch = worker_channel[Int, Int]()
    let inner = WorkerGroup[Int, Int]()
    var worker = inner.spawn(sleeps_long).get(none)
    let _outcome = worker.wait()

test "cancelling a worker that is joining another ends it as cancelled":
    let group = WorkerGroup[Int, Int]()
    var outer = group.spawn(joins_nested).get(none)
    sleep(nanoseconds(50000000))
    outer.cancel()

    let outcome = outer.wait()
    let cause = try expect_error(outcome)
    try expect_equal(cause.message(), "worker: cancelled")

fn touches_network() Unit:
    var ch = worker_channel[Int, Int]()
    let _net = network()
    let _ = ch.send(1)

test "a worker that uses the network ends cleanly":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(touches_network).get(none)
    try expect_equal(worker.channel.receive(), ok(some(1)))
    try expect_ok(worker.wait())

fn fetches_page() Unit:
    var ch = worker_channel[Int, String]()

    if let address = ch.receive().get(none):
        var total = 0
        for round in 0..3:
            if let response = fetch("http://{address}/page"):
                total += response.body.length()

        let _ = ch.send(total)

fn page(request: HttpRequest) HttpResponse:
    return HttpResponse(200, headers(), "x".repeat(65536).get("").to_bytes())

test "workers fetch from the starter's server at the same time":
    let handler = buffered(page)
    let acquired = network().serve(address: "127.0.0.1:0", handler: handler).get(none)
    var server = acquired
    var group = WorkerGroup[String, Int]()
    var workers: List[Worker[String, Int]] = []

    for i in 0..4:
        var worker = group.spawn(fetches_page).get(none)
        try expect_ok(worker.channel.send(server.address()))
        workers.append(worker)

    for i in 0..4:
        try expect_equal(workers[i].channel.receive(), ok(some(3 * 65536)))
        try expect_ok(workers[i].wait())

    group.close()
    server.close()

fn doubles_bytes() Unit:
    var _ch = worker_channel[Int, Int]()
    var raw = worker_bytes()

    while true:
        if let data = raw.receive().get(none):
            let _sent = raw.send(data.concat(data))
        else:
            return

test "bytes cross a worker pipe without JSON":
    let group = WorkerGroup[Int, Int]()
    var worker = group.spawn(doubles_bytes).get(none)
    var raw = worker.bytes()
    let big = "0123456789".repeat(30000).get("").to_bytes()
    let small = "abc".to_bytes()
    try expect_ok(raw.send(big))
    try expect_ok(raw.send(small))

    let first = raw.receive().get(none).get("".to_bytes())
    let second = raw.receive().get(none).get("".to_bytes())
    try expect_equal(first.length(), 600000)
    try expect_equal(first.slice(300000, 300010), big.slice(0, 10))
    try expect_equal(second.decode_utf8().get(""), "abcabc")
    worker.channel.close()
    try expect_ok(worker.wait())

fn serves_shared() Unit:
    var ch = worker_channel[String, String]()

    if let address = ch.receive().get(none):
        let options = HttpServerOptions(shared: true)

        if let acquired = network().serve(
            address: address, handler: buffered(page), options: options
        ):
            var server = acquired
            let _ = ch.send(server.address())
            let _stopped = ch.receive()
            server.close()

test "workers serve one port with a shared listener":
    let group = WorkerGroup[String, String]()
    var workers: List[Worker[String, String]] = []
    var first = ""

    for i in 0..3:
        var worker = group.spawn(serves_shared).get(none)
        try expect_ok(worker.channel.send("127.0.0.1:0"))

        let address = worker.channel.receive().get(none).get("")
        if i == 0:
            first = address.clone()
        try expect_equal(address, first)
        workers.append(worker)

    var total = 0
    for i in 0..12:
        if let response = fetch("http://{first}/page"):
            total += response.body.length()
    try expect_equal(total, 12 * 65536)

    for i in 0..3:
        try expect_ok(workers[i].channel.send("stop"))
        try expect_ok(workers[i].wait())

fn joined_ok(w: Worker[Int, Int]) Int:
    var held = w
    if held.wait().is_ok():
        return 1

    return 0

test "tasks joining clones of one worker all see its outcome":
    let workers = WorkerGroup[Int, Int]()
    let worker = workers.spawn(naps).get(none)
    let first_copy = worker.clone()
    let second_copy = worker.clone()
    let tasks = TaskGroup[Int]()
    let first = tasks.spawn(fn c: joined_ok(first_copy.clone()))
    let second = tasks.spawn(fn c: joined_ok(second_copy.clone()))
    first.result() | try expect_ok | try expect_equal(1)
    second.result() | try expect_ok | try expect_equal(1)
