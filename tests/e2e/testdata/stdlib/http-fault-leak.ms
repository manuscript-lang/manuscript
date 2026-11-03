import send, recv from "./support/conn.ms"
import expect_ok from "@std/test/test.ms"
import HttpExchange from "@std/net/http.ms"
import connect, serve from "@std/net/net.ms"
import Bytes from "@std/bytes.ms"
import memory_usage from "@std/os/process.ms"

fn faulting(var exchange: HttpExchange) Unit!:
    let big = "x".repeat(1000000).get("")
    let xs: List[Int] = []
    let n = xs[big.length()]
    if big.length() + n > 5: return ok(unit)

    return ok(unit)

test "a faulting handler releases the values its frames own":
    let server = serve(address: "127.0.0.1:0", handler: faulting) | try expect_ok
    let before = (memory_usage() | try expect_ok).resident

    for i in 0..60:
        var client = connect(server.address(), 2.seconds()).wait() | try expect_ok
        try send(var client, "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")

        let reply_bytes = try recv(var client, 3.seconds())
        let head = reply_bytes.get(Bytes([])).decode_utf8().get("")
        if not head.starts_with("HTTP/1.1 500"): return error(Error(head))

    // Each leaked fault kept 1 MB, so 60 faults would grow the process by 60 MB.
    let grown = (memory_usage() | try expect_ok).resident - before
    if grown > 20000000: return error(Error("resident memory grew {grown} bytes"))
