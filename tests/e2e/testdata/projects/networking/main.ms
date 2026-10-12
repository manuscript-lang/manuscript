import panic from "@std/faults.ms"

import Process from "@std/cli.ms"
import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import HttpError from "@std/http.ms"
import WebSocketError from "@std/websocket.ms"
import map_error from "@std/result.ms"
import IoError from "@std/io.ms"
import HttpExchange from "@std/http.ms"
import HttpServerOptions from "@std/http.ms"
import HttpClientOptions from "@std/http.ms"
import TlsOptions from "@std/tls.ms"
import WebSocketOptions from "@std/websocket.ms"

fn websocket_error(cause: WebSocketError) -> HttpError:
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
            return HttpError.Failed(message: message)

fn echo(exchange: HttpExchange & Shareable) -> Result[Unit, HttpError]:
    if exchange.path() == "/ws":
        with socket = try map_error(result: exchange.upgrade(allowed_origins: [], subprotocols: ["echo"], max_message_bytes: 1024), transform: websocket_error):
            match try map_error(result: socket.receive(), transform: websocket_error):
                some(message):
                    let sent = try map_error(result: socket.send(data: message.data, text: message.text), transform: websocket_error)
                none:
                    return ok(value: unit)
        return ok(value: unit)
    let headers = Map[String, List[String]]().with_entry(key: "X-Test", value: ["stream"])
    let started = try exchange.send_headers(status: 200, headers: headers)
    match exchange.write(data: "hello from streaming Manuscript".to_bytes()):
        ok(_):
            return ok(value: unit)
        error(_):
            return error(cause: HttpError.Failed(message: "write failed"))

fn exercise(process: Process) -> Result[Unit, HttpError]:
    let tls = TlsOptions(server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "", alpn: [], require_client_certificate: false)
    let server_options = HttpServerOptions(max_requests: 8, max_body_bytes: 1024, max_response_bytes: 1024, max_header_bytes: 65536, timeout: 3.seconds, grace: 0.milliseconds, tls: none)
    with server = try process.network.serve_stream(address: "127.0.0.1:0", handler: echo, options: server_options):
        let client_options = HttpClientOptions(max_redirects: 2, max_idle_connections: 4, max_header_bytes: 65536, idle_timeout: 10.seconds, decompress: true, cookies: true, tls: tls)
        with client = try process.network.http_client(options: client_options):
            with response = try client.send(method: "GET", url: "http://{server.address()}/", headers: Map[String, String](), body: "".to_bytes(), max_response_bytes: 1024, timeout: 2.seconds):
                if not (response.status() == 200):
                    return panic(message: "check failed")
                match response.read(max_bytes: 1024):
                    ok(part):
                        match part:
                            some(data):
                                if not (data.to_text() == some(value: "hello from streaming Manuscript")):
                                    return panic(message: "check failed")
                            none:
                                return panic(message: "Unexpected case")
                    error(_):
                        return panic(message: "Unexpected case")
        let websocket_options = WebSocketOptions(max_message_bytes: 1024, timeout: 2.seconds, tls: tls, compression: false)
        with socket = try map_error(result: process.network.web_socket(url: "ws://{server.address()}/ws", headers: Map[String, String](), subprotocols: ["echo"], options: websocket_options), transform: websocket_error):
            if not (socket.subprotocol() == "echo"):
                return panic(message: "check failed")
            let sent = try map_error(result: socket.send(data: "echo me".to_bytes(), text: true), transform: websocket_error)
            match try map_error(result: socket.receive(), transform: websocket_error):
                some(message):
                    if not (message.text):
                        return panic(message: "check failed")
                    if not (message.data.to_text() == some(value: "echo me")):
                        return panic(message: "check failed")
                none:
                    return panic(message: "Unexpected case")
    return ok(value: unit)

export fn main(process: Process) -> Int:
    match exercise(process: process):
        ok(_):
            return 0
        error(_):
            return 1
