# conform: tags=control-flow,faults,formatter,interpolation,modules,optional,parser,stdlib-http,stdlib-net,stdlib-sse,stdlib-testing,testing,tier-io,try-result,with-cleanup
# conform: phase=parse
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
from "@std/sse.ms" import body_stream, reader, next_event
from "@std/net.ms" import network

# Writes a CRLF stream whose chunks split a line ending and a multi-byte scalar.
def stream_events(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let sent = headers()
    try sent.append("Content-Type", "text/event-stream")
    try exchange.send_headers(200, sent)
    exchange.write("event: greet\r\ndata: h").get()
    exchange.write_bytes("é".to_bytes().slice(0, 1).get()).get()
    exchange.write_bytes(f"\u{e9}!\r".to_bytes().slice(1, 4).get()).get()
    exchange.write("\n\r\n: keepalive\n\ndata: second\n\n").get()
    return ok(())

test "HTTP response bodies decode as SSE and close with the reader":
    with let server = try network().serve(
        "127.0.0.1:0", stream_events, HttpServerOptions()
    ):
        with let client = try network().http_client(HttpClientOptions()):
            let response = try client.request(
                HttpMethod.Get, f"http://{server.address()}/", headers()
            )
            let status = response.metadata().status
            var events = try reader(body_stream(response))
            let first = (try next_event(var events)).get()
            let second = (try next_event(var events)).get()
            if first.event != "greet" or first.data != f"h\u{e9}!": return fail(
                f"first event {first.data}"
            )

            try expect_false(second.event != "message" or second.data != "second")
            try expect_false((try next_event(var events)).is_some())
            events.close()
            try expect_equal(status, 200)
