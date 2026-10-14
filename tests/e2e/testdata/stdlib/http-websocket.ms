import network from "@std/net.ms"
import {HttpExchange, HttpError, HttpServerOptions, HttpClientOptions} from "@std/http.ms"
import {WebSocketOptions, WebSocketError} from "@std/websocket.ms"
import TlsOptions from "@std/tls.ms"
import {List, Map} from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
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
        with socket = value(
            exchange.upgrade(
                allowed_origins: [],
                subprotocols: ["echo"],
                max_message_bytes: 1024
            )
        ):
            let message = value(socket.receive()).unwrap()
            let sent = value(socket.send(data: message.data, text: message.text))

        return ok(unit)

    let headers = Map[String, List[String]]().add(
        key: "X-Test",
        value: ["manuscript"]
    )
    let started = value(exchange.send_headers(status: 201, headers: headers))
    let written = value(
        exchange.write("hello".to_bytes())
    )
    return ok(unit)

test "HTTP buffered and streaming clients call a Manuscript handler":
    let net = network()
    let options = HttpServerOptions(
        max_requests: 4,
        timeout: 3.seconds,
        grace: 0.seconds,
        tls: none
    )

    with server = value(
        net.serve_stream(
            address: "127.0.0.1:0",
            handler: echo,
            options: options
        )
    ):
        let url = "http://{server.address()}/"
        let response = value(
            net.request(
                method: "GET",
                url: url,
                headers: Map[String, String](),
                body: "".to_bytes(),
                timeout: 2.seconds
            )
        )
        if response.status != 201 or response.body != "hello".to_bytes(): return panic(
            "buffered HTTP"
        )
        if response.headers.get("X-Test") != some(["manuscript"]): return panic(
            "HTTP header"
        )

        let client_options = HttpClientOptions(
            decompress: true,
            cookies: true,
            tls: tls_options()
        )

        with client = value(net.http_client(client_options)):
            with body = value(
                client.send(
                    method: "GET",
                    url: url,
                    headers: Map[String, String](),
                    body: "".to_bytes(),
                    max_response_bytes: 5,
                    timeout: 2.seconds
                )
            ):
                if body.status() != 201: return panic("streaming status")
                if value(
                    body.read(5)
                ).unwrap() != "hello".to_bytes(): return panic("streaming bytes")
                if not value(
                    body.read(5)
                ).is_none(): return panic("streaming EOF")

        let limited: Result[Unit, HttpError] = error(HttpError.LimitExceeded)

        match net.request(
            method: "GET",
            url: url,
            headers: Map[String, String](),
            body: "".to_bytes(),
            max_response_bytes: 4,
            timeout: 2.seconds
        ):
            ok(_): return panic("HTTP output budget ignored")

            error(cause):
                if cause != HttpError.LimitExceeded: return panic("HTTP output error")

test "WebSocket negotiates a protocol and echoes a text frame":
    let net = network()
    let options = HttpServerOptions(
        timeout: 3.seconds,
        grace: 0.seconds,
        tls: none
    )

    with server = value(
        net.serve_stream(
            address: "127.0.0.1:0",
            handler: echo,
            options: options
        )
    ):
        let client_options = WebSocketOptions(
            max_message_bytes: 1024,
            timeout: 2.seconds,
            tls: tls_options(),
            compression: false
        )

        with socket = value(
            net.web_socket(
                url: "ws://{server.address()}/ws",
                headers: Map[String, String](),
                subprotocols: ["echo"],
                options: client_options
            )
        ):
            if socket.subprotocol() != "echo": return panic("WebSocket subprotocol")

            let sent = value(
                socket.send(
                    data: "é🙂".to_bytes(),
                    text: true
                )
            )
            let message = value(socket.receive()).unwrap()
            if not message.text or message.data != "é🙂".to_bytes(): return panic(
                "WebSocket echo"
            )

fn report_host(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let hosts = exchange.headers().get("Host").unwrap_or([])
    let started = value(exchange.send_headers(status: 200, headers: Map[String, List[String]]()))
    let written = value(exchange.write(hosts.join(",").to_bytes()))
    return ok(value: unit)

test "HTTP streaming handlers see the Host request header":
    let net = network()
    let options = HttpServerOptions(max_requests: 2, timeout: 3.seconds, grace: 0.seconds, tls: none)

    with server = value(
        net.serve_stream(
            address: "127.0.0.1:0",
            handler: report_host,
            options: options
        )
    ):
        let response = value(
            net.request(
                method: "GET",
                url: "http://{server.address()}/",
                headers: Map[String, String](),
                body: "".to_bytes(),
                timeout: 2.seconds
            )
        )
        if response.body != server.address().to_bytes(): return panic("Host header missing")
