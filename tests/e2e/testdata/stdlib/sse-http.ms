import {
    headers,
    HttpClientOptions,
    HttpError,
    HttpExchange,
    HttpMethod,
    HttpServerOptions
} from "@std/http.ms"
import {borrow_body, reader, next_event} from "@std/sse.ms"
import network from "@std/net.ms"
import panic from "@std/faults.ms"

# Writes a CRLF stream whose chunks split a line ending and a multi-byte scalar.
fn stream_events(exchange: HttpExchange) Result[Unit, HttpError]:
    let sent = headers()
    try sent.append("Content-Type", "text/event-stream".to_bytes())
    try exchange.send_headers(200, sent)
    exchange.write("event: greet\r\ndata: h".to_bytes()).get()
    exchange.write("é".to_bytes().slice(0, 1).get()).get()
    exchange.write("\u{e9}!\r".to_bytes().slice(1, 4).get()).get()
    exchange.write("\n\r\n: keepalive\n\ndata: second\n\n".to_bytes()).get()
    return ok(unit)

test "HTTP response bodies decode as SSE without being closed by the reader":
    with server = try network().serve_stream(
        "127.0.0.1:0",
        stream_events,
        HttpServerOptions()
    ):
        with client = try network().http_client(HttpClientOptions()):
            with response = try client.request(
                HttpMethod.Get,
                "http://{server.address()}/",
                headers()
            ):
                let events = try reader(borrow_body(response))
                let first = (try next_event(events)).get()
                let second = (try next_event(events)).get()
                if first.event != "greet" or first.data != "h\u{e9}!": panic(
                    "first event {first.data}"
                )
                if second.event != "message" or second.data != "second": panic(
                    "second event"
                )
                if (try next_event(events)).is_some(): panic("end of response")
                if response.metadata().status != 200: panic(
                    "the response stays usable after decoding"
                )
