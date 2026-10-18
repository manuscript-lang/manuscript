import {
    headers,
    HttpMethod,
    HttpError,
    HttpExchange,
    HttpServerOptions,
    HttpClientOptions
} from "@std/http.ms"
import network from "@std/net.ms"
import panic from "@std/faults.ms"
import {WebSocket, WebSocketError, WebSocketOptions} from "@std/websocket.ms"
import TlsOptions from "@std/tls.ms"

fn relay(socket: WebSocket) Result[Unit, WebSocketError]:
    if let message = try socket.receive():
        try socket.send_bytes(message.data, text: message.text)
    return ok(unit)

fn echo(exchange: HttpExchange) Result[Unit, HttpError]:
    if exchange.path() == "/ws":
        if let acquired = exchange.upgrade([], ["echo"], 1024):
            with socket = acquired:
                if relay(socket).is_error():
                    return error(HttpError.Failed("websocket relay failed"))
            return ok(unit)

        return error(HttpError.Failed("websocket upgrade failed"))

    let fields = headers()
    try fields.append("X-Test", "stream".to_bytes())
    try exchange.send_headers(200, fields)
    if exchange.write("hello from streaming Manuscript").is_error():
        return error(HttpError.Failed("write failed"))

    return ok(unit)

fn exercise() Result[Unit, Error]:
    let tls = TlsOptions(
        server_name: "",
        roots_pem: "",
        certificate_pem: "",
        private_key_pem: "",
        alpn: [],
        require_client_certificate: false
    )
    let server_options = HttpServerOptions(
        max_requests: 8,
        max_body_bytes: 1024,
        max_response_bytes: 1024,
        max_header_bytes: 65536,
        timeout: 3.seconds,
        grace: 0.milliseconds,
        tls: none
    )

    with server = try network().serve_stream("127.0.0.1:0", echo, server_options):
        let client_options = HttpClientOptions(
            max_redirects: 2,
            max_idle_connections: 4,
            max_header_bytes: 65536,
            idle_timeout: 10.seconds,
            decompress: true,
            cookies: true,
            tls
        )

        with client = try network().http_client(client_options):
            with response = try client.request(
                method: HttpMethod.Get,
                url: "http://{server.address()}/",
                headers: headers(),
                body: "",
                max_response_bytes: 1024,
                timeout: 2.seconds
            ):
                if not (response.metadata().status == 200):
                    return panic("check failed")

                if let data = try response.read(1024):
                    if data.decode_utf8() != some("hello from streaming Manuscript"):
                        return panic("check failed")
                else:
                    return panic("Unexpected case")

        let websocket_options = WebSocketOptions(
            max_message_bytes: 1024,
            timeout: 2.seconds,
            tls,
            compression: false
        )

        with socket = try network().web_socket(
            url: "ws://{server.address()}/ws",
            headers: headers(),
            subprotocols: ["echo"],
            options: websocket_options
        ):
            if not (socket.subprotocol() == "echo"):
                return panic("check failed")

            try socket.send("echo me")

            if let message = try socket.receive():
                if not (message.text):
                    return panic("check failed")
                if not (message.data.decode_utf8() == some("echo me")):
                    return panic("check failed")
            else:
                return panic("Unexpected case")

    return ok(unit)

export fn main() Int:
    if exercise().is_error():
        return 1

    return 0
