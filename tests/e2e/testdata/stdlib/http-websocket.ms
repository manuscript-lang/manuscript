import {headers, HttpMethod} from "@std/http.ms"
import {text_headers, list_headers} from "./support/http.ms"
import network from "@std/net.ms"
import {HttpExchange, HttpError, HttpServerOptions, HttpClientOptions} from "@std/http.ms"
import {WebSocketOptions, WebSocketError} from "@std/websocket.ms"
import TlsOptions from "@std/tls.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"

fn tls_options() -> TlsOptions:
    return TlsOptions(
        server_name: "",
        roots_pem: "",
        certificate_pem: "",
        private_key_pem: "",
        alpn: [],
        require_client_certificate: false
    )

fn echo(exchange: HttpExchange) -> Result[Unit, HttpError]:
    if exchange.path() == "/ws":
        with socket = exchange.upgrade(
            allowed_origins: [],
            subprotocols: ["echo"],
            max_message_bytes: 1024
        ) | value:
            let message = value(socket.receive()).unwrap()
            let sent = socket.send(data: message.data, text: message.text) | value

        return ok(unit)

    let headers = list_headers(
        Map[String, List[String]]().add(key: "X-Test", value: ["manuscript"])
    )
    let started = exchange.send_headers(status: 201, headers: headers) | value
    let written = exchange.write("hello".to_bytes()) | value
    return ok(unit)

test "HTTP buffered and streaming clients call a Manuscript handler":
    let net = network()
    let options = HttpServerOptions(
        max_requests: 4,
        timeout: 3.seconds,
        grace: 0.seconds,
        tls: none
    )

    with server = net.serve_stream(
        address: "127.0.0.1:0",
        handler: echo,
        options: options
    ) | value:
        let url = "http://{server.address()}/"
        let response = net.request(
            method: HttpMethod.Get,
            url: url,
            headers: text_headers(Map[String, String]()),
            body: "".to_bytes(),
            timeout: 2.seconds
        ) | value
        if response.metadata().status != 201 or response.body != "hello".to_bytes(): return panic(
            "buffered HTTP"
        )
        if value(response.metadata().headers.text("X-Test")) != some(["manuscript"]): return panic(
            "HTTP header"
        )

        let client_options = HttpClientOptions(
            decompress: true,
            cookies: true,
            tls: tls_options()
        )

        with client = net.http_client(client_options) | value:
            with body = client.request(
                method: HttpMethod.Get,
                url: url,
                headers: text_headers(Map[String, String]()),
                body: "".to_bytes(),
                max_response_bytes: 5,
                timeout: 2.seconds
            ) | value:
                if body.metadata().status != 201: return panic("streaming status")
                if value(body.read(5)).unwrap() != "hello".to_bytes(): return panic(
                    "streaming bytes"
                )
                if not value(body.read(5)).is_none(): return panic("streaming EOF")

        let limited: Result[Unit, HttpError] = error(HttpError.LimitExceeded)
        let budgeted = net.request(
            method: HttpMethod.Get,
            url: url,
            headers: text_headers(Map[String, String]()),
            body: "".to_bytes(),
            max_response_bytes: 4,
            timeout: 2.seconds
        )
        if budgeted.is_ok(): return panic("HTTP output budget ignored")
        if budgeted.unwrap_error() != HttpError.LimitExceeded: return panic(
            "HTTP output error"
        )

test "WebSocket negotiates a protocol and echoes a text frame":
    let net = network()
    let options = HttpServerOptions(timeout: 3.seconds, grace: 0.seconds, tls: none)

    with server = net.serve_stream(
        address: "127.0.0.1:0",
        handler: echo,
        options: options
    ) | value:
        let client_options = WebSocketOptions(
            max_message_bytes: 1024,
            timeout: 2.seconds,
            tls: tls_options(),
            compression: false
        )

        with socket = net.web_socket(
            url: "ws://{server.address()}/ws",
            headers: text_headers(Map[String, String]()),
            subprotocols: ["echo"],
            options: client_options
        ) | value:
            if socket.subprotocol() != "echo": return panic("WebSocket subprotocol")

            let sent = socket.send(data: "é🙂".to_bytes(), text: true) | value
            let message = value(socket.receive()).unwrap()
            if not message.text or message.data != "é🙂".to_bytes(): return panic(
                "WebSocket echo"
            )

fn report_host(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let hosts = value(exchange.headers().text("Host")).unwrap_or([])
    let started = exchange.send_headers(status: 200, headers: headers()) | value
    let written = exchange.write(hosts.join(",").to_bytes()) | value
    return ok(unit)

test "HTTP streaming handlers see the Host request header":
    let net = network()
    let options = HttpServerOptions(
        max_requests: 2,
        timeout: 3.seconds,
        grace: 0.seconds,
        tls: none
    )

    with server = net.serve_stream(
        address: "127.0.0.1:0",
        handler: report_host,
        options: options
    ) | value:
        let response = net.request(
            method: HttpMethod.Get,
            url: "http://{server.address()}/",
            headers: text_headers(Map[String, String]()),
            body: "".to_bytes(),
            timeout: 2.seconds
        ) | value
        if response.body != server.address().to_bytes(): return panic(
            "Host header missing"
        )

test "HTTP requests reject an empty method":
    let empty = network() | .request(
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
