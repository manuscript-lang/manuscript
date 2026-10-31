import expect_ok from "@std/test.ms"
import HttpError, HttpExchange from "@std/http.ms"
import TextError from "@std/core.ms"
import network from "@std/net.ms"
import Bytes from "@std/bytes.ms"
import control from "@std/process.ms"

fn faulting(exchange: HttpExchange) Unit!HttpError:
    let big = "x".repeat(1000000).get("")
    let xs: List[Int] = []
    let n = xs[big.length()]
    if big.length() + n > 5: return ok(unit)

    return ok(unit)

test "a faulting handler releases the values its frames own":
    let net = network()
    let server = net.serve(address: "127.0.0.1:0", handler: faulting) | try expect_ok
    let before = (control().memory_usage() | try expect_ok).resident

    for i in 0..60:
        let client = net.connect(server.address(), 2.seconds) | try expect_ok
        client.write(
            "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n", 2.seconds
        ) | try expect_ok

        let reply_bytes = client.read(timeout: 3.seconds) | try expect_ok
        let head = reply_bytes.get(Bytes([])).decode_utf8().get("")
        if not head.starts_with("HTTP/1.1 500"): return error(TextError(head))

    # Each leaked fault kept 1 MB, so 60 faults would grow the process by 60 MB.
    let grown = (control().memory_usage() | try expect_ok).resident - before
    if grown > 20000000: return error(TextError("resident memory grew {grown} bytes"))
