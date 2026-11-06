import send, recv from "./support/conn.ms"
import expect_equal, expect_error, expect_ok from "@std/test/test.ms"
import (
    headers,
    HttpRequest,
    HttpResponse,
    buffered,
    HttpServerOptions
) from "@std/net/http.ms"
import connect, serve from "@std/net/net.ms"
import Bytes from "@std/bytes.ms"

fn ok_route(request: HttpRequest) HttpResponse:
    return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())

test "serve caps the request header block":
    let server = serve(address: "127.0.0.1:0", handler: buffered(ok_route)) | try expect_ok
    var client = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
    let filler = "a".repeat(2000000) | try expect_ok
    let head = "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\nX: {filler}\r\n\r\n"

    // The server may answer and close before the whole head is written.
    let _written = send(var client, head)
    let reply = recv(var client, 5.seconds()) | try expect_ok
    let text = reply.get().decode_utf8().get("")
    if not text.starts_with("HTTP/1.1 431"): return error(
        Error("oversized header block was not rejected: {text}")
    )

test "serve timeout closes idle connections":
    let handler = ok_route
    let server = serve(
        address: "127.0.0.1:0", handler: buffered(handler),
        options: HttpServerOptions(timeout: 300.milliseconds())
    ) | try expect_ok
    var silent = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
    let closed = recv(var silent, 3.seconds()) | try expect_ok
    if let _data = closed: return error(Error("silent connection was answered"))

    try silent.close()

    var reused = connect(server.address(), timeout: 2.seconds()).wait() | try expect_ok
    send(var reused, "GET / HTTP/1.1\r\nHost: t\r\n\r\n") | try expect_ok

    let first = recv(var reused, 2.seconds()) | try expect_ok
    let answered = first.get(Bytes([]))
    if answered.length() == 0: return error(Error("no response"))

    let after = recv(var reused, 3.seconds()) | try expect_ok
    if let _data = after: return error(Error("idle keep-alive connection stayed open"))

test "serve rejects a zero request timeout":
    let failure = try expect_error(
        serve(
            address: "127.0.0.1:0", handler: buffered(ok_route),
            options: HttpServerOptions(timeout: 0.seconds())
        )
    )
    try expect_equal(failure, Error("HTTP: invalid input", kind: "EINVAL"))
