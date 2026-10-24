# conform: tags=control-flow,faults,interpolation,modules,optional,stdlib-http,stdlib-net,stdlib-sse,stdlib-testing,testing,tier-io,try-result,with-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/sse-http.ms
from "@std/testing.ms" import expect_equal, expect_false, fail
from "@std/http.ms" import (
    headers,
    HttpClientOptions,
    HttpError,
    HttpExchange,
    HttpMethod,
    HttpServerOptions
)
from "@std/sse.ms" import borrow_body, reader, next_event
from "@std/net.ms" import network

# Writes a CRLF stream whose chunks split a line ending and a multi-byte scalar.
def stream_events(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let sent = headers()
    try sent.append("Content-Type", "text/event-stream".to_bytes())
    try exchange.send_headers(200, sent)
    exchange.write("event: greet\r\ndata: h").get()
    exchange.write_bytes("é".to_bytes().slice(0, 1).get()).get()
    exchange.write_bytes(f"\u{e9}!\r".to_bytes().slice(1, 4).get()).get()
    exchange.write("\n\r\n: keepalive\n\ndata: second\n\n").get()
    return ok(())

test "HTTP response bodies decode as SSE without being closed by the reader":
    with try network().serve_stream("127.0.0.1:0", stream_events, HttpServerOptions()) as server:
        with try network().http_client(HttpClientOptions()) as client:
            with try client.request(
                HttpMethod.Get, f"http://{server.address()}/", headers()
            ) as response:
                var events = try reader(borrow_body(response))
                let first = (try next_event(var events)).get()
                let second = (try next_event(var events)).get()
                if first.event != "greet" or first.data != f"h\u{e9}!": return fail(
                    f"first event {first.data}"
                )

                try expect_false(second.event != "message" or second.data != "second")
                try expect_false((try next_event(var events)).is_some())
                try expect_equal(response.metadata().status, 200)
