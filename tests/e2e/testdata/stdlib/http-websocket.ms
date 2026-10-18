import expect_error from "@std/testing.ms"
import {headers, HttpMethod} from "@std/http.ms"
import {text_headers, list_headers} from "./support/http.ms"
import network from "@std/net.ms"
import {HttpExchange, HttpError, HttpServerOptions, HttpClientOptions} from "@std/http.ms"
import {WebSocketOptions} from "@std/websocket.ms"
import TlsOptions from "@std/tls.ms"
import panic from "@std/faults.ms"

fn tls_options() TlsOptions:
    return TlsOptions(
        server_name: "",
        roots_pem: "",
        certificate_pem: "",
        private_key_pem: "",
        alpn: [],
        require_client_certificate: false
    )

fn echo(exchange: HttpExchange) Result[Unit, HttpError]:
    if exchange.path() == "/ws":
        with socket = (
            exchange
            .upgrade(
                allowed_origins: [],
                subprotocols: ["echo"],
                max_message_bytes: 1024
            )
            .unwrap()
        ):
            let message = socket.receive().unwrap().unwrap()
            socket.send(data: message.data, text: message.text).unwrap()

        return ok(unit)

    let headers = list_headers(
        Map[String, List[String]]().add(key: "X-Test", value: ["manuscript"])
    )
    try exchange.send_headers(status: 201, headers: headers)
    exchange.write("hello".to_bytes()).unwrap()
    return ok(unit)

test "HTTP buffered and streaming clients call a Manuscript handler":
    let net = network()
    let options = HttpServerOptions(
        max_requests: 4,
        timeout: 3.seconds,
        grace: 0.seconds,
        tls: none
    )

    with server = try net.serve_stream(
        address: "127.0.0.1:0",
        handler: echo,
        options: options
    ):
        let url = "http://{server.address()}/"
        let response = try net.request(
            method: HttpMethod.Get,
            url: url,
            headers: text_headers(Map[String, String]()),
            body: "".to_bytes(),
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
                method: HttpMethod.Get,
                url: url,
                headers: text_headers(Map[String, String]()),
                body: "".to_bytes(),
                max_response_bytes: 5,
                timeout: 2.seconds
            ):
                if body.metadata().status != 201: return panic("streaming status")
                if (try body.read(5)).unwrap() != "hello".to_bytes(): return panic(
                    "streaming bytes"
                )
                if not (try body.read(5)).is_none(): return panic("streaming EOF")

        let budget = net.request(
            method: HttpMethod.Get,
            url: url,
            headers: text_headers(Map[String, String]()),
            body: "".to_bytes(),
            max_response_bytes: 4,
            timeout: 2.seconds
        )
        if (try expect_error(budget)) != HttpError.LimitExceeded: return panic(
            "HTTP output error"
        )

test "WebSocket negotiates a protocol and echoes a text frame":
    let net = network()
    let options = HttpServerOptions(timeout: 3.seconds, grace: 0.seconds, tls: none)

    with server = try net.serve_stream(
        address: "127.0.0.1:0",
        handler: echo,
        options: options
    ):
        let client_options = WebSocketOptions(
            max_message_bytes: 1024,
            timeout: 2.seconds,
            tls: tls_options(),
            compression: false
        )

        with socket = try net.web_socket(
            url: "ws://{server.address()}/ws",
            headers: text_headers(Map[String, String]()),
            subprotocols: ["echo"],
            options: client_options
        ):
            if socket.subprotocol() != "echo": return panic("WebSocket subprotocol")

            try socket.send(data: "é🙂".to_bytes(), text: true)
            let message = (try socket.receive()).unwrap()
            if not message.text or message.data != "é🙂".to_bytes(): return panic(
                "WebSocket echo"
            )

fn report_host(exchange: HttpExchange) Result[Unit, HttpError]:
    let hosts = (try exchange.headers().text("Host")).unwrap_or([])
    try exchange.send_headers(status: 200, headers: headers())
    exchange.write(hosts.join(",").to_bytes()).unwrap()
    return ok(unit)

test "HTTP streaming handlers see the Host request header":
    let net = network()
    let options = HttpServerOptions(
        max_requests: 2,
        timeout: 3.seconds,
        grace: 0.seconds,
        tls: none
    )

    with server = try net.serve_stream(
        address: "127.0.0.1:0",
        handler: report_host,
        options: options
    ):
        let response = try net.request(
            method: HttpMethod.Get,
            url: "http://{server.address()}/",
            headers: text_headers(Map[String, String]()),
            body: "".to_bytes(),
            timeout: 2.seconds
        )
        if response.body != server.address().to_bytes(): return panic(
            "Host header missing"
        )

test "HTTP requests reject an empty method":
    let empty = network().request(
        method: HttpMethod.Custom(value: ""),
        url: "http://127.0.0.1:1/",
        headers: text_headers(Map[String, String]()),
        body: "".to_bytes(),
        timeout: 1.seconds
    )
    if empty.is_ok(): return panic("empty method accepted")
    if empty.unwrap_error() != HttpError.InvalidInput: return panic(
        "empty method error"
    )
