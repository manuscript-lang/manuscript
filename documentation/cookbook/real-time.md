+++
title = "WebSockets and server-sent events"
weight = 14
+++

# WebSockets and server-sent events

Push data to a client as it happens. A WebSocket carries messages both ways; server-sent events (SSE) stream events one way over plain HTTP.

## Echo over a WebSocket

Save as `echo.ms`. The handler calls `upgrade` to turn the request into a `WebSocket`, which has an `input` stream to read and an `output` stream to write. `serve` with port 0 picks a free port, so this runs as one program with the client in the same process.

<!-- manuscript-example: {"mode":"run","stdout":"hello\n"} -->
```manuscript
import (
    HttpExchange, upgrade from "@std/net/http.ms",
    serve, web_socket from "@std/net/net.ms",
    WebSocketKind, WebSocketMessage from "@std/net/websocket.ms",
)

fn echo(var exchange HttpExchange) Void! {
    var socket = upgrade(exchange)?
    message := socket.input.next()?
    if message == null { return ok() }

    socket.output.write(message)?
    socket.close()?
}

fn main() Void! {
    var server = serve("127.0.0.1:0", echo)?
    var client = web_socket(f"ws://{server.address()}/")?
    client.output.write(
        WebSocketMessage(data: "hello".to_bytes(), kind: WebSocketKind.Text)
    )?

    reply := client.input.next()?
    if reply == null { return ok() }
    print(reply.data.decode_utf8() or "")
    client.close()?
    server.close()?
}
```

- `input.next()` returns `null` when the peer closes normally, so a loop over `socket.input` ends by itself.
- `upgrade` checks the `Origin` header against `allowed_origins`, offers `subprotocols`, and bounds a message with `max_message_bytes`. Set the last one for any server that faces the internet.
- Use `wss://` with the client's `WebSocketOptions(tls: ...)` for TLS: see [HTTPS and certificates](tls.md).

## Stream events with SSE

Save as `ticks.ms`. The server sends headers with `Content-Type: text/event-stream` and then writes events as blank-line-separated blocks. `sse_events` turns the response body into a stream of `SseEvent` values with `event`, `data`, `id` and `retry`, however the bytes were split.

Destructure the response to take its body: a stream is a resource and cannot be moved out of a field.

<!-- manuscript-example: {"mode":"run","stdout":"tick: 1\ntick: 2\n"} -->
```manuscript
import (
    HttpExchange, HttpMethod, headers from "@std/net/http.ms",
    http_client, serve from "@std/net/net.ms",
    sse_events from "@std/net/sse.ms",
)

fn ticker(var exchange HttpExchange) Void! {
    var sent = headers()
    sent.append("Content-Type", "text/event-stream")?
    exchange.send_headers(200, sent)?
    exchange.write("event: tick\ndata: 1\n\n")?
    exchange.write("event: tick\ndata: 2\n\n")?
}

fn main() Void! {
    var server = serve("127.0.0.1:0", ticker)?
    client := http_client()?
    response := client.request(
        HttpMethod.Get,
        f"http://{server.address()}/",
        headers(),
    )?
    {body: payload} := response
    var events = sse_events(payload)
    for event in events {
        print(f"{event.event}: {event.data}")
    }
    events.close()?
    server.close()?
}
```

- A stream that ends in the middle of an event fails with `EBADMSG`, and the unfinished event is never delivered.
- `SseLimits(max_line_bytes: ..., max_event_bytes: ...)` bounds a hostile server.
- Choose SSE when only the server sends and you want plain HTTP, reconnection and proxies to just work; choose a WebSocket when the client also sends.
