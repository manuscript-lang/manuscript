# conform: tags=control-flow,diagnostics,generics,interpolation,match,modules,optional,stdlib-http,stdlib-io,stdlib-net,stdlib-testing,stdlib-tls,stdlib-websocket,tier-io,try-result,scope-cleanup
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/networking/main.ms
import expect_equal, expect_false, expect_true, fail from "@std/test/test.ms"
import headers, HttpMethod, buffered from "@std/net/http.ms"
import http_client, serve, web_socket from "@std/net/net.ms"
import HttpExchange from "@std/net/http.ms"
import HttpServerOptions from "@std/net/http.ms"
import HttpClientOptions from "@std/net/http.ms"
import TlsOptions from "@std/net/net.ms"
import WebSocketOptions from "@std/net/net.ms"

fn echo(exchange: HttpExchange) Unit!:
    if exchange.path() == "/ws":
        var socket = try exchange.upgrade(
            allowed_origins: [], subprotocols: ["echo"], max_message_bytes: 1024
        )

        match try socket.receive():
            message:
                let _sent = try socket.send_bytes(
                    data: message.data, text: message.text
                )
            none:
                return ok(unit)

        socket.close().get(none)
        return ok(unit)

    var fields = headers()
    let _appended = try fields.append("X-Test", "stream")
    let _started = try exchange.send_headers(status: 200, headers: fields)

    match exchange.write(data: "hello from streaming Manuscript"):
        ok(_):
            return ok(unit)
        error(_):
            return error(Error("write failed", kind: ErrorCategory.Failed))

fn exercise() Unit!:
    let tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "",
        alpn: [], require_client_certificate: false
    )
    let server_options = HttpServerOptions(
        max_requests: 8, max_body_bytes: 1024, max_response_bytes: 1024,
        max_header_bytes: 65536, timeout: 3.seconds, grace: 0.milliseconds, tls: none
    )
    var server = try serve(
        address: "127.0.0.1:0", handler: echo, options: server_options
    )
    let client_options = HttpClientOptions(
        max_redirects: 2, max_idle_connections: 4, max_header_bytes: 65536,
        idle_timeout: 10.seconds, decompress: true, cookies: true, tls: tls.clone()
    )
    var client = try http_client(options: client_options)
    let response = try client.request(
        method: HttpMethod.Get, url: "http://{server.address()}/", headers: headers(),
        body: "", max_response_bytes: 1024, timeout: 2.seconds
    )
    response.metadata().status | try expect_equal(200)

    let part = match response.read(max_bytes: 1024):
        ok(part): part
        error(_):
            return fail(message: "Unexpected case")

    match part:
        data:
            try expect_false(
                not (
                    data.decode_utf8() == "hello from streaming Manuscript"
                )
            )
        none:
            return fail(message: "Unexpected case")

    try client.close()

    let websocket_options = WebSocketOptions(
        max_message_bytes: 1024, timeout: 2.seconds, tls: tls, compression: false
    )
    let socket = try web_socket(
        url: "ws://{server.address()}/ws", headers: headers(),
        subprotocols: ["echo"], options: websocket_options
    )
    socket.subprotocol() | try expect_equal("echo")

    let _sent = try socket.send(data: "echo me")

    match try socket.receive():
        message:
            (message.text) | try expect_true
            try expect_equal(message.data.decode_utf8(), "echo me")
        none:
            return fail(message: "Unexpected case")

    try server.close()
    return ok(unit)

export fn main() Int:
    match exercise():
        ok(_):
            return 0
        error(_):
            return 1
