from "@std/test.ms" import expect_equal, expect_error, expect_ok
from "@std/http.ms" import HttpError, headers, HttpRequest, HttpResponse, buffered, HttpServerOptions
from "@std/core.ms" import TextError
from "@std/net.ms" import network
from "@std/bytes.ms" import Bytes

def ok_route(request: HttpRequest) -> HttpResponse:
    return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())

test "serve caps the request header block":
    let net = network()
    let server = net.serve(
        address: "127.0.0.1:0", handler: buffered(ok_route)
    ) | try expect_ok
    let client = net.connect(server.address(), 2.seconds) | try expect_ok
    let filler = "a".repeat(2000000) | try expect_ok
    let head = f"GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\nX: {filler}\r\n\r\n"

    # The server may answer and close before the whole head is written.
    let _written = client.write(head, 5.seconds)
    let reply = client.read(timeout: 5.seconds) | try expect_ok
    let text = reply.get().decode_utf8().get("")
    if not text.starts_with("HTTP/1.1 431"): return error(
        TextError(f"oversized header block was not rejected: {text}")
    )

test "serve timeout closes idle connections":
    let net = network()
    let handler = ok_route
    let server = net.serve(
        address: "127.0.0.1:0", handler: buffered(handler),
        options: HttpServerOptions(timeout: 300.milliseconds)
    ) | try expect_ok
    var silent = net.connect(server.address(), 2.seconds) | try expect_ok
    let closed = silent.read(timeout: 3.seconds) | try expect_ok
    if let _data = closed: return error(TextError("silent connection was answered"))

    silent.close()

    let reused = net.connect(server.address(), 2.seconds) | try expect_ok
    reused.write("GET / HTTP/1.1\r\nHost: t\r\n\r\n", 2.seconds) | try expect_ok

    let first = reused.read(timeout: 2.seconds) | try expect_ok
    let answered = first.get(Bytes([]))
    if answered.length() == 0: return error(TextError("no response"))

    let after = reused.read(timeout: 3.seconds) | try expect_ok
    if let _data = after: return error(
        TextError("idle keep-alive connection stayed open")
    )

test "serve rejects a zero request timeout":
    let net = network()
    let failure = try expect_error(
        net.serve(
            address: "127.0.0.1:0", handler: buffered(ok_route),
            options: HttpServerOptions(timeout: 0.seconds)
        )
    )
    try expect_equal(failure, HttpError.InvalidInput)
