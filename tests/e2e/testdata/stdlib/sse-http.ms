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
import value from "./support/results.ms"

# Writes a CRLF stream whose chunks split a line ending and a multi-byte scalar.
fn stream_events(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let sent = headers()
    sent.append("Content-Type", "text/event-stream".to_bytes()) | value
    exchange.send_headers(status: 200, headers: sent) | value
    exchange.write("event: greet\r\ndata: h".to_bytes()) | value
    exchange.write("é".to_bytes().slice(0, 1).unwrap()) | value
    exchange.write("\u{e9}!\r".to_bytes().slice(1, 4).unwrap()) | value
    exchange.write("\n\r\n: keepalive\n\ndata: second\n\n".to_bytes()) | value
    return ok(unit)

test "HTTP response bodies decode as SSE without being closed by the reader":
    with server = value(
        network().serve_stream(
            address: "127.0.0.1:0",
            handler: stream_events,
            options: HttpServerOptions()
        )
    ):
        with client = value(network().http_client(options: HttpClientOptions())):
            with response = client.request(
                method: HttpMethod.Get,
                url: "http://{server.address()}/",
                headers: headers()
            ) | value:
                let events = borrow_body(response) | reader | value
                let first = value(next_event(events)).unwrap()
                let second = value(next_event(events)).unwrap()
                if first.event != "greet" or first.data != "h\u{e9}!": panic(
                    "first event {first.data}"
                )
                if second.event != "message" or second.data != "second": panic(
                    "second event"
                )
                if value(next_event(events)).is_some(): panic("end of response")
                if response.metadata().status != 200: panic(
                    "the response stays usable after decoding"
                )
