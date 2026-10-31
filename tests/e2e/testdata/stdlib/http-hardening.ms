import expect_ok, expect_equal from "@std/test.ms"
import (
    headers,
    reply,
    text,
    HttpError,
    HttpExchange,
    HttpRequest,
    HttpResponse,
    buffered,
    HttpServerOptions
) from "@std/http.ms"
import TextError from "@std/core.ms"
import Connection, connect, serve from "@std/net.ms"
import Bytes from "@std/bytes.ms"
import read_file, temporary, write_file_bytes from "@std/fs.ms"
import sleep from "@std/time.ms"

fn ok_route(request: HttpRequest) HttpResponse:
    return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())

fn slow_route(request: HttpRequest) HttpResponse:
    sleep(30.seconds)
    return HttpResponse(status: 200, headers: headers(), body: "late".to_bytes())

test "serve ends a connection that trickles its request head":
    let server = serve(
        address: "127.0.0.1:0", handler: buffered(ok_route),
        options: HttpServerOptions(timeout: 400.milliseconds)
    ) | try expect_ok
    let client = connect(server.address(), 2.seconds) | try expect_ok
    client.write("GET / HTTP/1.1\r\nHost: t\r\nX-Slow: ", 2.seconds) | try expect_ok

    # One byte every 100 ms never completes the head; the budget still runs out.
    var sent = 0

    while sent < 30:
        sleep(100.milliseconds)

        let written = client.write("a", 1.seconds)
        if written.is_error(): break

        sent += 1

    # The server closes the connection, so a write fails before the trickle ends. The
    # read may then see an error (a reset on macOS) instead of an end of stream.
    if sent == 30: return error(TextError("trickled request head was never cut off"))

    if let reply = client.read(timeout: 3.seconds):
        let text = reply.get(Bytes([])).decode_utf8().get("")
        if text.starts_with("HTTP/1.1 200"): return error(
            TextError("incomplete request was served: {text}")
        )

test "close cancels a handler that outlives the grace period":
    var server = serve(
        address: "127.0.0.1:0", handler: buffered(slow_route),
        options: HttpServerOptions(grace: 200.milliseconds)
    ) | try expect_ok
    let client = connect(server.address(), 2.seconds) | try expect_ok
    client.write("GET / HTTP/1.1\r\nHost: t\r\n\r\n", 2.seconds) | try expect_ok
    sleep(100.milliseconds)
    try server.close()

    # An error here is the connection ending (a reset on macOS); only a served reply fails.
    if let reply = client.read(timeout: 5.seconds):
        let text = reply.get(Bytes([])).decode_utf8().get("")
        if text.starts_with("HTTP/1.1 200"): return error(
            TextError("handler finished instead of being cancelled")
        )

fn expect_file_reply(conn: Connection) Unit!:
    let reply = conn.read(timeout: 10.seconds) | try expect_ok
    let text = reply.get(Bytes([])).decode_utf8().get("")
    if not text.starts_with("HTTP/1.1 200"): return error(
        TextError("file handler failed: {text}")
    )

    return ok(unit)

test "serve answers requests while handlers read and write files":
    var dir = temporary("ms-http-io") | try expect_ok
    let root = dir.path()
    let payload = ("0123456789abcdef".repeat(262144) | try expect_ok).to_bytes()

    fn io_route(request: HttpRequest) HttpResponse:
        let path = "{root}/slot{request.query}.bin"
        let wrote = write_file_bytes(path, payload.clone(), replace: true)
        if wrote.is_error():
            return HttpResponse(500, headers(), "write".to_bytes())

        let read = read_file(path)
        if read.is_error():
            return HttpResponse(500, headers(), "read".to_bytes())

        return HttpResponse(200, headers(), "{read.get().length()}".to_bytes())

    var server = serve(address: "127.0.0.1:0", handler: buffered(io_route)) | try expect_ok
    let a = connect(server.address(), 2.seconds) | try expect_ok
    let b = connect(server.address(), 2.seconds) | try expect_ok
    a.write(
        "GET /io?1 HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n", 2.seconds
    ) | try expect_ok
    b.write(
        "GET /io?2 HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n", 2.seconds
    ) | try expect_ok
    try expect_file_reply(a)
    try expect_file_reply(b)
    try server.close()
    try dir.close()

fn oversized(exchange: HttpExchange) Unit!HttpError:
    return reply(exchange, text(200, "z".repeat(5000).get("")))

test "serve answers 500 when a whole response exceeds max_response_bytes":
    let server = serve(
        address: "127.0.0.1:0", handler: oversized,
        options: HttpServerOptions(max_response_bytes: 100)
    ) | try expect_ok
    let client = connect(server.address(), 2.seconds) | try expect_ok
    client.write(
        "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n", 2.seconds
    ) | try expect_ok

    let reply_bytes = client.read(timeout: 3.seconds) | try expect_ok
    let head = reply_bytes.get(Bytes([])).decode_utf8().get("")
    if not head.starts_with("HTTP/1.1 500"): return error(
        TextError("expected a 500 reply, got: {head}")
    )

fn raw_status(address: String, request: String) String!:
    let client = connect(address, 2.seconds) | try expect_ok
    client.write(request, 2.seconds) | try expect_ok

    let reply = client.read(timeout: 2.seconds) | try expect_ok
    let text = reply.get(Bytes([])).decode_utf8().get("")
    return ok(text.split("\r\n")[0].clone())

test "asterisk-form target is accepted only for OPTIONS":
    let server = serve(address: "127.0.0.1:0", handler: buffered(ok_route)) | try expect_ok
    let tail = "HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n"
    let get = raw_status(server.address(), "GET * {tail}") | try expect_ok
    let options = raw_status(server.address(), "OPTIONS * {tail}") | try expect_ok
    if get != "HTTP/1.1 400 Bad Request": return error(
        TextError("GET * answered: {get}")
    )
    if options != "HTTP/1.1 200 OK": return error(
        TextError("OPTIONS * answered: {options}")
    )
