from "@std/testing.ms" import expect_equal, expect_false, expect_true, fail
from "@std/http.ms" import headers, HttpMethod, buffered
from "@std/net.ms" import network
from "@std/http.ms" import HttpError
from "@std/net.ms" import WebSocketError
from "@std/io.ms" import IoError
from "@std/http.ms" import HttpExchange
from "@std/http.ms" import HttpServerOptions
from "@std/http.ms" import HttpClientOptions
from "@std/net.ms" import TlsOptions
from "@std/net.ms" import WebSocketOptions

def websocket_error(cause: WebSocketError) -> HttpError:
    match cause:
        case InvalidInput:
            return HttpError.InvalidInput
        case InvalidData:
            return HttpError.InvalidData
        case LimitExceeded:
            return HttpError.LimitExceeded
        case PermissionDenied:
            return HttpError.PermissionDenied
        case Closed:
            return HttpError.Closed
        case Timeout:
            return HttpError.Timeout
        case Failed(message):
            return HttpError.Failed(message)

def socket_result[T](result: Result[T, WebSocketError]) -> Result[T, HttpError]:
    match result:
        case ok(value):
            return ok(value)
        case error(cause):
            return error(websocket_error(cause))

def echo(exchange: HttpExchange) -> Result[Unit, HttpError]:
    if exchange.path() == "/ws":
        with let socket = try socket_result(
            result: exchange.upgrade(
                allowed_origins: [], subprotocols: ["echo"], max_message_bytes: 1024
            )
        ):
            match try socket_result(result: socket.receive()):
                case some(message):
                    let sent = try socket_result(
                        result: socket.send_bytes(
                            data: message.data, text: message.text
                        )
                    )
                case none:
                    return ok(())

        return ok(())

    let fields = headers()
    let appended = try fields.append("X-Test", "stream".to_bytes())
    let started = try exchange.send_headers(status: 200, headers: fields)

    match exchange.write(data: "hello from streaming Manuscript"):
        case ok(_):
            return ok(())
        case error(_):
            return error(HttpError.Failed("write failed"))

def exercise() -> Result[Unit, Error]:
    let tls = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "",
        alpn: [], require_client_certificate: False
    )
    let server_options = HttpServerOptions(
        max_requests: 8, max_body_bytes: 1024, max_response_bytes: 1024,
        max_header_bytes: 65536, timeout: 3.seconds, grace: 0.milliseconds, tls: none
    )

    with let server = try network().serve(
        address: "127.0.0.1:0", handler: echo, options: server_options
    ):
        let client_options = HttpClientOptions(
            max_redirects: 2, max_idle_connections: 4, max_header_bytes: 65536,
            idle_timeout: 10.seconds, decompress: True, cookies: True, tls: tls.clone()
        )

        with let client = try network().http_client(options: client_options):
            with let response = try client.request(
                method: HttpMethod.Get, url: f"http://{server.address()}/",
                headers: headers(), body: "", max_response_bytes: 1024,
                timeout: 2.seconds
            ):
                response.metadata().status | try expect_equal(200)

                let part = match response.read(max_bytes: 1024):
                    case ok(part): part
                    case error(_):
                        return fail(message: "Unexpected case")

                match part:
                    case some(data):
                        try expect_false(
                            not (
                                data.decode_utf8() == some(
                                    "hello from streaming Manuscript"
                                )
                            )
                        )
                    case none:
                        return fail(message: "Unexpected case")

        let websocket_options = WebSocketOptions(
            max_message_bytes: 1024, timeout: 2.seconds, tls: tls, compression: False
        )

        with let socket = try socket_result(
            result: network().web_socket(
                url: f"ws://{server.address()}/ws", headers: headers(),
                subprotocols: ["echo"], options: websocket_options
            )
        ):
            socket.subprotocol() | try expect_equal("echo")

            let sent = try socket_result(result: socket.send(data: "echo me"))

            match try socket_result(result: socket.receive()):
                case some(message):
                    (message.text) | try expect_true
                    try expect_equal(message.data.decode_utf8(), some("echo me"))
                case none:
                    return fail(message: "Unexpected case")

    return ok(())

export def main() -> Int:
    match exercise():
        case ok(_):
            return 0
        case error(_):
            return 1
