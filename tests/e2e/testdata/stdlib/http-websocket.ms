import expect_error from "@std/testing.ms"
import {headers, HttpMethod} from "@std/http.ms"
import {text_headers, list_headers} from "./support/http.ms"
import network from "@std/net.ms"
import {HttpExchange, HttpError, HttpServerOptions, HttpClientOptions} from "@std/http.ms"
import {WebSocketOptions} from "@std/websocket.ms"
import TlsOptions from "@std/tls.ms"
import panic from "@std/faults.ms"

fn tls_options() TlsOptions:
    return TlsOptions("", "", "", "", [], require_client_certificate: false)

fn echo(exchange: HttpExchange) Result[Unit, HttpError]:
    if exchange.path() == "/ws":
        with socket = (exchange.upgrade([], ["echo"], 1024).get()):
            let message = socket.receive().get().get()
            socket.send_bytes(message.data, text: message.text).get()

        return ok(unit)

    let headers = list_headers(
        Map[String, List[String]]().add("X-Test", ["manuscript"])
    )
    try exchange.send_headers(201, headers)
    exchange.write("hello").get()
    return ok(unit)

test "HTTP buffered and streaming clients call a Manuscript handler":
    let net = network()
    let options = HttpServerOptions(4, timeout: 3.seconds, grace: 0.seconds, tls: none)

    with server = try net.serve_stream("127.0.0.1:0", echo, options):
        let url = "http://{server.address()}/"
        let response = try net.request(
            HttpMethod.Get,
            url,
            text_headers(Map[String, String]()),
            "",
            timeout: 2.seconds
        )
        if response.metadata().status != 201 or response.body != "hello".to_bytes(): return panic(
            "buffered HTTP"
        )
        if (try response.metadata().headers.text("X-Test")) != some(["manuscript"]): return panic(
            "HTTP header"
        )

        let client_options = HttpClientOptions(
            decompress: true,
            cookies: true,
            tls: tls_options()
        )

        with client = try net.http_client(client_options):
            with body = try client.request(
                HttpMethod.Get,
                url,
                text_headers(Map[String, String]()),
                "",
                5,
                2.seconds
            ):
                if body.metadata().status != 201: return panic("streaming status")
                if (try body.read(5)).get() != "hello".to_bytes(): return panic(
                    "streaming bytes"
                )
                if not (try body.read(5)).is_none(): return panic("streaming EOF")

        let budget = net.request(
            HttpMethod.Get,
            url,
            text_headers(Map[String, String]()),
            "",
            4,
            2.seconds
        )
        if (try expect_error(budget)) != HttpError.LimitExceeded: return panic(
            "HTTP output error"
        )

test "WebSocket negotiates a protocol and echoes a text frame":
    let net = network()
    let options = HttpServerOptions(timeout: 3.seconds, grace: 0.seconds, tls: none)

    with server = try net.serve_stream("127.0.0.1:0", echo, options):
        let client_options = WebSocketOptions(
            1024,
            2.seconds,
            tls_options(),
            compression: false
        )

        with socket = try net.web_socket(
            "ws://{server.address()}/ws",
            text_headers(Map[String, String]()),
            ["echo"],
            client_options
        ):
            if socket.subprotocol() != "echo": return panic("WebSocket subprotocol")

            try socket.send("é🙂")
            let message = (try socket.receive()).get()
            if not message.text or message.data != "é🙂".to_bytes(): return panic(
                "WebSocket echo"
            )

fn report_host(exchange: HttpExchange) Result[Unit, HttpError]:
    let hosts = (try exchange.headers().text("Host")).get([])
    try exchange.send_headers(200, headers())
    exchange.write(hosts.join(",")).get()
    return ok(unit)

test "HTTP streaming handlers see the Host request header":
    let net = network()
    let options = HttpServerOptions(2, timeout: 3.seconds, grace: 0.seconds, tls: none)

    with server = try net.serve_stream("127.0.0.1:0", report_host, options):
        let response = try net.request(
            HttpMethod.Get,
            "http://{server.address()}/",
            text_headers(Map[String, String]()),
            "",
            timeout: 2.seconds
        )
        if response.body != server.address().to_bytes(): return panic(
            "Host header missing"
        )

test "HTTP requests reject an empty method":
    let empty = network().request(
        HttpMethod.Custom(""),
        "http://127.0.0.1:1/",
        text_headers(Map[String, String]()),
        "",
        timeout: 1.seconds
    )
    if empty.is_ok(): return panic("empty method accepted")
    if empty.err() != HttpError.InvalidInput: return panic("empty method error")
