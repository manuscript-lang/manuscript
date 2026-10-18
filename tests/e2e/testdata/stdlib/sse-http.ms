import {expect_equal, expect_false, expect_ok, fail} from "@std/testing.ms"
import http_result from "./support/http.ms"
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

# Writes a CRLF stream whose chunks split a line ending and a multi-byte scalar.
fn stream_events(exchange: HttpExchange) -> Result[Unit, HttpError]:
    let sent = headers()
    (try sent.append("Content-Type", "text/event-stream".to_bytes()))
    (try exchange.send_headers(status: 200, headers: sent))
    (try http_result(exchange.write("event: greet\r\ndata: h".to_bytes())))
    (try http_result(exchange.write("é".to_bytes().slice(0, 1).unwrap())))
    (try http_result(exchange.write("\u{e9}!\r".to_bytes().slice(1, 4).unwrap())))
    (
        try http_result(
            exchange.write(
                "\n\r\n: keepalive\n\ndata: second\n\n".to_bytes()
            )
        )
    )
    return ok(unit)

test "HTTP response bodies decode as SSE without being closed by the reader":
    with server = (
        network().serve_stream(
            address: "127.0.0.1:0",
            handler: stream_events,
            options: HttpServerOptions()
        ) | try expect_ok
    ):
        with client = (
            network().http_client(
                options: HttpClientOptions()
            ) | try expect_ok
        ):
            with response = (
                client.request(
                    method: HttpMethod.Get,
                    url: "http://{server.address()}/",
                    headers: headers()
                ) | try expect_ok
            ):
                let events = (reader(input: borrow_body(response)) | try expect_ok)
                let first = (next_event(events) | try expect_ok).unwrap()
                let second = (next_event(events) | try expect_ok).unwrap()
                if first.event != "greet" or first.data != "h\u{e9}!": return fail(
                    "first event {first.data}"
                )

                (second.event != "message" or second.data != "second") | try expect_false
                (next_event(events) | try expect_ok).is_some() | try expect_false
                response.metadata().status | try expect_equal(expected: 200)
