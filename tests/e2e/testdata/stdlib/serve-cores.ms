import HttpRequest, HttpResponse, buffered, headers from "@std/net/http.ms"
import (Listener, serve_cores, serve_core, connect, listen) from "@std/net/net.ms"
import TaskGroup from "@std/concurrency/tasks.ms"
import sleep from "@std/os/time.ms"
import expect_equal, expect_error, expect_true from "@std/test/test.ms"

fn core() Unit:
    let tag = "hello"
    let handler = fn(request: HttpRequest) HttpResponse:
        return HttpResponse(status: 200, headers: headers(), body: tag.to_bytes())
    let served = serve_core(buffered(handler))
    let _ = served

fn run(listener: Listener) Unit!:
    return serve_cores(listener, core, 3)

fn get(address: String) String:
    var client = connect(address, 2.seconds).get()
    let _ = client.write("GET /x HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
    var text = ""

    while true:
        let chunk = client.read(none, 2.seconds)
        if chunk.is_error():
            break

        if let data = chunk.get(none):
            text = "{text}{data.decode_utf8().get("")}"
            continue

        break

    return text

test "serve_cores serves clients across workers and fails when accepting fails":
    let listener = try listen("127.0.0.1:0")
    let address = listener.address()
    var group = TaskGroup[Unit!]()
    group.spawn(fn ch: run(listener))

    for i in 0..5:
        let text = get(address)
        try expect_true(text.starts_with("HTTP/1.1 200 OK"))
        try expect_true(text.ends_with("hello"))

    try group.close()

test "serve_cores rejects fewer than one core":
    let listener = try listen("127.0.0.1:0")
    let outcome = serve_cores(listener, core, 0)
    try expect_true(outcome.is_error())

fn ends_at_once() Unit:
    return

fn serve_dead(listener: Listener) Unit!:
    return serve_cores(listener, ends_at_once, 2)

test "serve_cores closes the connection it could not hand to a worker":
    let listener = try listen("127.0.0.1:0")
    let address = listener.address()
    var group = TaskGroup[Unit!]()
    let serving = group.spawn(fn ch: serve_dead(listener))
    sleep(200.milliseconds)

    var client = try connect(address, 2.seconds)
    try expect_true(serving.result().get(ok(unit)).is_error())

    let chunk = client.read(none, 2.seconds)
    try expect_true(chunk.is_ok())
    try expect_true(chunk.get(none).is_none())

fn never_reads() Unit:
    sleep(30.seconds)

fn serve_idle(listener: Listener) Unit!:
    return serve_cores(listener, never_reads, 1)

test "serve_cores closes connections still queued for a cancelled worker":
    let listener = try listen("127.0.0.1:0")
    let address = listener.address()
    var group = TaskGroup[Unit!]()
    let serving = group.spawn(fn ch: serve_idle(listener))
    var client = try connect(address, 2.seconds)
    sleep(200.milliseconds)
    try group.close()
    serving.result() | try expect_error | try expect_equal(
        Error("task: closed", kind: ErrorCategory.Closed)
    )

    let chunk = client.read(none, 2.seconds)
    try expect_true(chunk.is_ok())
    try expect_true(chunk.get(none).is_none())
