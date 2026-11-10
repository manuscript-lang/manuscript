import (
    expect_equal, expect_false, expect_true, fail from "@std/test/test.ms",
    headers, HttpMethod, buffered, upgrade from "@std/net/http.ms",
    http_client, serve, web_socket from "@std/net/net.ms",
    HttpExchange from "@std/net/http.ms",
    HttpServerOptions from "@std/net/http.ms",
    HttpClientOptions from "@std/net/http.ms",
    TlsOptions from "@std/net/tls.ms",
    WebSocketOptions, WebSocketMessage, WebSocketKind from "@std/net/websocket.ms",
)

fn echo(var exchange: HttpExchange) Unit!:
    if exchange.path() == "/ws":
        var socket = try upgrade(
            var exchange, allowed_origins: [], subprotocols: ["echo"],
            max_message_bytes: 1024
        )

        match try socket.input.next():
            message:
                try socket.output.write(message)
            none:
                return ok(unit)

        try socket.close()
        return ok(unit)

    var fields = headers()
    let _appended = try fields.append("X-Test", "stream")
    try exchange.send_headers(200, fields)
    return exchange.write_bytes("hello from streaming Manuscript".to_bytes())

fn exercise() Unit!:
    let tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "",
        alpn: [], require_client_certificate: false
    )
    let server_options = HttpServerOptions(
        max_requests: 8, max_body_bytes: 1024, max_response_bytes: 1024,
        max_header_bytes: 65536, timeout: 3.seconds(), grace: 0.milliseconds(),
        tls: none
    )
    var server = try serve(
        address: "127.0.0.1:0", handler: echo, options: server_options
    )
    let client_options = HttpClientOptions(
        max_redirects: 2, max_idle_connections: 4, max_header_bytes: 65536,
        idle_timeout: 10.seconds(), decompress: true, cookies: true, tls: tls.clone()
    )
    var client = try http_client(options: client_options)
    var response = try client.request(
        method: HttpMethod.Get, url: "http://{server.address()}/", headers: headers(),
        body: "", max_response_bytes: 1024, timeout: 2.seconds()
    )
    response.metadata.status | try expect_equal(200)

    let part = try response.body.next()

    match part:
        data:
            try expect_false(
                not (
                    data.decode_utf8() == "hello from streaming Manuscript"
                )
            )
        none:
            return fail(message: "Unexpected case")

    try response.close()
    try client.close()

    let websocket_options = WebSocketOptions(
        headers: headers(), subprotocols: ["echo"], max_message_bytes: 1024,
        timeout: 2.seconds(), tls: tls, compression: false
    )
    var socket = try web_socket(
        url: "ws://{server.address()}/ws", options: websocket_options
    )
    socket.subprotocol | try expect_equal("echo")
    try socket.output.write(
        WebSocketMessage(data: "echo me".to_bytes(), kind: WebSocketKind.Text)
    )

    match try socket.input.next():
        message:
            try expect_true(message.kind == WebSocketKind.Text)
            try expect_equal(
                message.data.decode_utf8(), "echo me".to_bytes().decode_utf8()
            )
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
