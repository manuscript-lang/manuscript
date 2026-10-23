import {expect_ok} from "@std/testing.ms"
import {headers, HttpRequest, HttpResponse} from "@std/http.ms"
import TextError from "@std/core.ms"
import network from "@std/net.ms"
import Bytes from "@std/bytes.ms"

fn ok_route(request: HttpRequest) HttpResponse:
    return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())

test "serve caps the request header block":
    let net = network()

    with server = (net.serve(address: "127.0.0.1:0", handler: ok_route) | try expect_ok):
        with client = (net.connect(server.address(), 2.seconds) | try expect_ok):
            let filler = ("a".repeat(2000000) | try expect_ok)
            let head = "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\nX: {filler}\r\n\r\n"

            # The server may answer and close before the whole head is written.
            let _written = client.write(head, 5.seconds)
            let reply = (client.read(timeout: 5.seconds) | try expect_ok)
            let text = reply.get().decode_utf8().get("")
            if not text.starts_with("HTTP/1.1 431"): return error(
                TextError(
                    "oversized header block was not rejected: {text}"
                )
            )

test "serve timeout closes idle connections":
    let net = network()
    let handler = ok_route

    with server = (
        net.serve(
            address: "127.0.0.1:0", handler: handler, timeout: 300.milliseconds
        ) | try expect_ok
    ):
        with silent = (net.connect(server.address(), 2.seconds) | try expect_ok):
            let closed = (silent.read(timeout: 3.seconds) | try expect_ok)
            if let _data = closed: return error(
                TextError("silent connection was answered")
            )

        with reused = (net.connect(server.address(), 2.seconds) | try expect_ok):
            reused.write("GET / HTTP/1.1\r\nHost: t\r\n\r\n", 2.seconds) | try expect_ok

            let first = (reused.read(timeout: 2.seconds) | try expect_ok)
            let answered = first.get(Bytes([]))
            if answered.length() == 0: return error(TextError("no response"))

            let after = (reused.read(timeout: 3.seconds) | try expect_ok)
            if let _data = after: return error(
                TextError("idle keep-alive connection stayed open")
            )
