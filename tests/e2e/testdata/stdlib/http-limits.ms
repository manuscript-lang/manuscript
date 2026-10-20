import {expect_ok} from "@std/testing.ms"
import {headers, HttpRequest, HttpResponse} from "@std/http.ms"
import TextError from "@std/errors.ms"
import network from "@std/net.ms"

fn ok_route(request: HttpRequest) HttpResponse:
    return HttpResponse(status: 200, headers: headers(), body: "ok".to_bytes())

test "serve caps the request header block":
    let net = network()
    with server = (net.serve(address: "127.0.0.1:0", handler: ok_route) | try expect_ok):
        with client = (net.connect(server.address(), 2.seconds) | try expect_ok):
            let filler = ("a".repeat(2000000) | try expect_ok)
            let head = "GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\nX: {filler}\r\n\r\n"
            # The server may answer and close before the whole head is written.
            let written = client.write(head, 5.seconds)
            let reply = (client.read(timeout: 5.seconds) | try expect_ok)
            let text = reply.get().decode_utf8().get("")
            if not text.starts_with("HTTP/1.1 431"): return error(
                TextError("oversized header block was not rejected: {text}")
            )
