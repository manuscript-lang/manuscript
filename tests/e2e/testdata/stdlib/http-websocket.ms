import expect_equal, expect_false, expect_ok, expect_true, fail from "@std/test/test.ms"
import http_result from "./support/http.ms"
import headers, HttpMethod, buffered from "@std/net/http.ms"
import text_headers, list_headers from "./support/http.ms"
import http_client, request, serve, web_socket from "@std/net/net.ms"
import (
    HttpExchange,
    HttpError,
    HttpServerOptions,
    HttpClientOptions
) from "@std/net/http.ms"
import WebSocketOptions, WebSocketError from "@std/net/net.ms"
import TlsOptions from "@std/net/net.ms"

fn tls_options() TlsOptions:
    return TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "",
        alpn: [], require_client_certificate: false
    )

fn echo(var exchange: HttpExchange) Unit!HttpError:
    if exchange.path() == "/ws":
        var socket = (
            try http_result(
                exchange.upgrade(
                    allowed_origins: [], subprotocols: ["echo"], max_message_bytes: 1024
                )
            )
        )
        let message = (try http_result(socket.receive())).get()
        let _sent = (
            try http_result(
                socket.send_bytes(
                    data: message.data, text: message.text
                )
            )
        )
        socket.close().get(none)
        return ok(unit)

    var chain_1 = Map[String, List[String]]()
    chain_1.add(key: "X-Test", value: ["manuscript"])

    let headers = (try list_headers(chain_1))
    let _started = try exchange.send_headers(status: 201, headers: headers)
    let _written = (try http_result(exchange.write("hello")))
    return ok(unit)

test "HTTP buffered and streaming clients call a Manuscript handler":
    let options = HttpServerOptions(
        max_requests: 4, timeout: 3.seconds, grace: 0.seconds, tls: none
    )
    let server = serve(address: "127.0.0.1:0", handler: echo, options: options) | try expect_ok
    let url = "http://{server.address()}/"
    let response = request(
        method: HttpMethod.Get, url: url,
        headers: (try text_headers(Map[String, String]())), body: "", timeout: 2.seconds
    ) | try expect_ok
    try expect_false(
        (
            response.metadata().status != 201
            or response.body != "hello".to_bytes()
        )
    )
    response.metadata().headers.values("X-Test") | try expect_equal(["manuscript"])

    let client_options = HttpClientOptions(
        decompress: true, cookies: true, tls: tls_options()
    )
    var client = http_client(client_options) | try expect_ok
    let body = client.request(
        method: HttpMethod.Get, url: url,
        headers: (try text_headers(Map[String, String]())), body: "",
        max_response_bytes: 5, timeout: 2.seconds
    ) | try expect_ok
    body.metadata().status | try expect_equal(201)
    (body.read(5) | try expect_ok).get() | try expect_equal("hello".to_bytes())
    ((body.read(5) | try expect_ok).is_none()) | try expect_true
    try client.close()

    let _limited: Unit!HttpError = error(HttpError.LimitExceeded)

    match request(
        method: HttpMethod.Get, url: url,
        headers: (try text_headers(Map[String, String]())), body: "",
        max_response_bytes: 4, timeout: 2.seconds
    ):
        ok(_): return fail("HTTP output budget ignored")
        error(cause):
            try expect_equal(cause, HttpError.LimitExceeded)

test "WebSocket negotiates a protocol and echoes a text frame":
    let options = HttpServerOptions(timeout: 3.seconds, grace: 0.seconds, tls: none)
    let server = serve(address: "127.0.0.1:0", handler: echo, options: options) | try expect_ok
    let client_options = WebSocketOptions(
        max_message_bytes: 1024, timeout: 2.seconds, tls: tls_options(),
        compression: false
    )
    let socket = web_socket(
        url: "ws://{server.address()}/ws",
        headers: (try text_headers(Map[String, String]())), subprotocols: ["echo"],
        options: client_options
    ) | try expect_ok
    socket.subprotocol() | try expect_equal("echo")

    let _sent = socket.send(data: "é🙂") | try expect_ok
    let message = (socket.receive() | try expect_ok).get()
    (not message.text or message.data != "é🙂".to_bytes()) | try expect_false

fn report_host(var exchange: HttpExchange) Unit!HttpError:
    let hosts = exchange.headers().values("Host")
    let _started = try exchange.send_headers(status: 200, headers: headers())
    let _written = (try http_result(exchange.write(hosts.join(","))))
    return ok(unit)

test "HTTP streaming handlers see the Host request header":
    let options = HttpServerOptions(
        max_requests: 2, timeout: 3.seconds, grace: 0.seconds, tls: none
    )
    let server = serve(address: "127.0.0.1:0", handler: report_host, options: options) | try expect_ok
    let response = request(
        method: HttpMethod.Get, url: "http://{server.address()}/",
        headers: (try text_headers(Map[String, String]())), body: "", timeout: 2.seconds
    ) | try expect_ok
    response.body | try expect_equal(server.address().to_bytes())

test "HTTP requests reject an empty method":
    match request(
        method: HttpMethod.Custom(value: ""), url: "http://127.0.0.1:1/",
        headers: (try text_headers(Map[String, String]())), body: "", timeout: 1.seconds
    ):
        ok(_): return fail("empty method accepted")
        error(cause):
            try expect_equal(cause, HttpError.InvalidInput)
