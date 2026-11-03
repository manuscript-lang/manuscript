// conform: tags=control-flow,faults,interpolation,modules,optional,stdlib-http,stdlib-net,stdlib-sse,stdlib-testing,testing,tier-io,try-result,scope-cleanup
// conform: phase=test
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
fn stream_events(exchange: HttpExchange) Unit!:
    var live = exchange
    var sent = headers()
    try sent.append("Content-Type", "text/event-stream")
    try live.send_headers(200, sent)
    try live.write("event: greet\r\ndata: h")
    try live.write_bytes("é".to_bytes().slice(0, 1).get())
    try live.write_bytes("\u{e9}!\r".to_bytes().slice(1, 4).get())
    try live.write("\n\r\n: keepalive\n\ndata: second\n\n")
    return ok(unit)

test "HTTP response bodies decode as SSE and close with the reader":
    let server = try serve("127.0.0.1:0", stream_events, HttpServerOptions())
    let client = try http_client(HttpClientOptions())
    let response = try client.request(
        HttpMethod.Get, "http://{server.address()}/", headers()
    )
    let {metadata: head, body: payload} = response
    let status = head.status
    var events = sse_events(payload)
    let first = (try events.read().wait()).get()
    let second = (try events.read().wait()).get()
    if first.event != "greet" or first.data != "h\u{e9}!": return fail(
        "first event {first.data}"
    )

    try expect_false(second.event != "message" or second.data != "second")
    try expect_false((try events.read().wait()).is_some())
    try events.close()
    try expect_equal(status, 200)
