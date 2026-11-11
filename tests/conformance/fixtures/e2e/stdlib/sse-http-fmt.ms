// conform: tags=control-flow,faults,formatter,interpolation,modules,optional,parser,stdlib-http,stdlib-net,stdlib-sse,stdlib-testing,testing,tier-io,try-result,scope-cleanup
// conform: phase=parse
// conform: origin=tests/e2e/testdata/stdlib/sse-http.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"
import (
    headers,
    HttpClientOptions,
    HttpExchange,
    HttpMethod,
    HttpServerOptions
) from "@std/net/http.ms"
import sse_events from "@std/net/sse.ms"
import http_client, serve from "@std/net/net.ms"

// Writes a CRLF stream whose chunks split a line ending and a multi-byte scalar.
fn stream_events(var exchange: HttpExchange) Unit!:
    var sent = headers()
    sent.append("Content-Type", "text/event-stream")?
    exchange.send_headers(200, sent)?
    exchange.write("event: greet\r\ndata: h").get()
    exchange.write_bytes("é".to_bytes().slice(0, 1).get()).get()
    exchange.write_bytes("\u{e9}!\r".to_bytes().slice(1, 4).get()).get()
    exchange.write("\n\r\n: keepalive\n\ndata: second\n\n").get()

test "HTTP response bodies decode as SSE and close with the reader":
    server := serve("127.0.0.1:0", stream_events, HttpServerOptions())?
    client := http_client(HttpClientOptions())?
    response := client.request(
        HttpMethod.Get, "http://{server.address()}/", headers()
    )?
    {metadata: head, body: payload} := response
    status := head.status
    var events = sse_events(payload)
    first := (events.next()?).get()
    second := (events.next()?).get()
    if first.event != "greet" or first.data != "h\u{e9}!": return fail(
        "first event {first.data}"
    )

    expect_false(second.event != "message" or second.data != "second")?
    expect_false((events.next()?).is_some())?
    events.close()?
    expect_equal(status, 200)?
