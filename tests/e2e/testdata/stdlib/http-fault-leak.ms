import send, recv from "./support/conn.ms"
import expect_ok from "@std/test/test.ms"
import HttpExchange from "@std/net/http.ms"
import connect, serve from "@std/net/net.ms"
import Bytes from "@std/bytes.ms"
import memory_usage from "@std/os/system.ms"
import PromiseOptions from "@std/concurrency/promise.ms"
import fetch from "@std/net/fetch.ms"
import sleep from "@std/time.ms"

fn faulting(var exchange: HttpExchange) Unit!:
    big := "x".repeat(1000000).get("")
    xs: List[Int] = []
    n := xs[big.length()]
    if big.length() + n > 5: return ok(unit)

    return ok(unit)

test "a faulting handler releases the values its frames own":
    server := serve(address: "127.0.0.1:0", handler: faulting) | try expect_ok
    before := (memory_usage() | try expect_ok).resident

    for i in 0..60:
        var client = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
        try send(var client, "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")

        reply_bytes := try recv(var client, 3.seconds())
        head := reply_bytes.get(Bytes([])).decode_utf8().get("")
        if not head.starts_with("HTTP/1.1 500"): return error(Error(head))

    // Each leaked fault kept 1 MB, so 60 faults would grow the process by 60 MB.
    grown := (memory_usage() | try expect_ok).resident - before
    if grown > 20000000: return error(Error("resident memory grew {grown} bytes"))

fn hanging(var exchange: HttpExchange) Unit!:
    try sleep(30.seconds()).wait()
    return ok(unit)

test "a fetch cancelled by its timeout releases its read buffer":
    server := serve(address: "127.0.0.1:0", handler: hanging) | try expect_ok
    url := "http://{server.address()}/"

    // Warm up the thread's buffers and the connection pool before measuring.
    for i in 0..20:
        _ := fetch(url).with(
            options: PromiseOptions(timeout: 5.milliseconds())
        ).wait()

    before := (memory_usage() | try expect_ok).resident

    for i in 0..300:
        timed_out := fetch(url).with(
            options: PromiseOptions(timeout: 5.milliseconds())
        ).wait()
        if timed_out.is_ok(): return error(Error("a hanging handler answered"))

    // Each cancelled read leaked a 64 KiB buffer, so 300 fetches grew the process by about 19 MB.
    grown := (memory_usage() | try expect_ok).resident - before
    if grown > 8000000: return error(Error("resident memory grew {grown} bytes"))

test "a fetch cancelled by its timeout frees the request state its frames own":
    server := serve(address: "127.0.0.1:0", handler: hanging) | try expect_ok
    url := "http://{server.address()}/"
    for i in 0..200:
        _ := fetch(url).with(
            options: PromiseOptions(timeout: 5.milliseconds())
        ).wait()

    before := (memory_usage() | try expect_ok).heap_used

    for i in 0..2000:
        timed_out := fetch(url).with(
            options: PromiseOptions(timeout: 5.milliseconds())
        ).wait()
        if timed_out.is_ok(): return error(Error("a hanging handler answered"))

    // The method, URLs, header vectors and pool key leaked about 340 bytes per cancelled fetch.
    grown := (memory_usage() | try expect_ok).heap_used - before
    if grown > 2000 * 64: return error(
        Error("heap grew {grown} bytes over 2000 cancelled fetches")
    )
