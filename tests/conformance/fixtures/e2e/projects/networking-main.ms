# conform: tags=control-flow,diagnostics,generics,interpolation,match,modules,optional,stdlib-http,stdlib-io,stdlib-net,stdlib-testing,stdlib-tls,stdlib-websocket,tier-io,try-result,with-cleanup
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/networking/main.ms
import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"
import {headers, HttpMethod} from "@std/http.ms"
import network from "@std/net.ms"
import HttpError from "@std/http.ms"
import WebSocketError from "@std/net.ms"
import IoError from "@std/io.ms"
import HttpExchange from "@std/http.ms"
import HttpServerOptions from "@std/http.ms"
import HttpClientOptions from "@std/http.ms"
import TlsOptions from "@std/net.ms"
import WebSocketOptions from "@std/net.ms"

fn websocket_error(cause: WebSocketError) HttpError:
    match cause:
        InvalidInput:
            return HttpError.InvalidInput
        InvalidData:
            return HttpError.InvalidData
        LimitExceeded:
            return HttpError.LimitExceeded
        PermissionDenied:
            return HttpError.PermissionDenied
        Closed:
            return HttpError.Closed
        Timeout:
            return HttpError.Timeout
        Failed(message):
            return HttpError.Failed(message)

fn socket_result[T](result: Result[T, WebSocketError]) Result[T, HttpError]:
    match result:
        ok(value):
            return ok(value)
        error(cause):
            return error(websocket_error(cause))

fn echo(exchange: HttpExchange) Result[Unit, HttpError]:
    if exchange.path() == "/ws":
        with socket = try socket_result(
            result: exchange.upgrade(
                allowed_origins: [],
                subprotocols: ["echo"],
                max_message_bytes: 1024
            )
        ):
            match try socket_result(result: socket.receive()):
                some(message):
                    let sent = try socket_result(
                        result: socket.send_bytes(
                            data: message.data,
                            text: message.text
                        )
                    )
                none:
                    return ok(unit)

        return ok(unit)

    let fields = headers()
    let appended = try fields.append("X-Test", "stream".to_bytes())
    let started = try exchange.send_headers(status: 200, headers: fields)

    match exchange.write(data: "hello from streaming Manuscript"):
        ok(_):
            return ok(unit)
        error(_):
            return error(HttpError.Failed("write failed"))

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

    with server = try network().serve_stream(
        address: "127.0.0.1:0",
        handler: echo,
        options: server_options
    ):
        let client_options = HttpClientOptions(
            max_redirects: 2,
            max_idle_connections: 4,
            max_header_bytes: 65536,
            idle_timeout: 10.seconds,
            decompress: true,
            cookies: true,
            tls: tls.clone()
        )

        with client = try network().http_client(options: client_options):
            with response = try client.request(
                method: HttpMethod.Get,
                url: "http://{server.address()}/",
                headers: headers(),
                body: "",
                max_response_bytes: 1024,
                timeout: 2.seconds
            ):
                response.metadata().status | try expect_equal(200)

                let part = match response.read(max_bytes: 1024):
                    ok(part): part
                    error(_):
                        return fail(message: "Unexpected case")

                match part:
                    some(data):
                        try expect_false(
                            not (
                                data.decode_utf8() == some(
                                    "hello from streaming Manuscript"
                                )
                            )
                        )
                    none:
                        return fail(message: "Unexpected case")

        let websocket_options = WebSocketOptions(
            max_message_bytes: 1024,
            timeout: 2.seconds,
            tls: tls,
            compression: false
        )

        with socket = try socket_result(
            result: network().web_socket(
                url: "ws://{server.address()}/ws",
                headers: headers(),
                subprotocols: ["echo"],
                options: websocket_options
            )
        ):
            socket.subprotocol() | try expect_equal("echo")
            let sent = try socket_result(result: socket.send(data: "echo me"))

            match try socket_result(result: socket.receive()):
                some(message):
                    (message.text) | try expect_true
                    try expect_equal(message.data.decode_utf8(), some("echo me"))
                none:
                    return fail(message: "Unexpected case")

    return ok(unit)

export fn main() Int:
    match exercise():
        ok(_):
            return 0
        error(_):
            return 1
