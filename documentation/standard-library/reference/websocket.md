+++
title = "websocket"
+++

# @std/websocket.ms

Import each required symbol with `import Name from "@std/websocket.ms"`.

## WebSocket {data-api-kind="Interface"}

A WebSocket connection. Send and receive byte messages with an explicit text flag.

```manuscript
interface WebSocket:
    fn close() -> Unit
    fn ping(data: Bytes) -> Result[Unit, WebSocketError]
    fn receive() -> Result[Optional[WebSocketMessage], WebSocketError]
    fn send(data: Bytes, text: Bool) -> Result[Unit, WebSocketError]
    fn subprotocol() -> String
```

## WebSocketError {data-api-kind="Alternative"}

Errors returned by WebSocket handshakes, message limits, timeouts, or closed sockets.

```manuscript
type WebSocketError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case PermissionDenied
    case Closed
    case Timeout
    case Failed(message: String)
```

```manuscript
impl Error for WebSocketError:
    fn message() -> String:
```

## WebSocketMessage {data-api-kind="Record"}

A received message and whether its payload is UTF-8 text.

```manuscript
type WebSocketMessage:
    data: Bytes
    text: Bool
```

## WebSocketOptions {data-api-kind="Record"}

WebSocket message, timeout, TLS, and per-message compression settings.

```manuscript
type WebSocketOptions:
    max_message_bytes: Optional[Int] = none
    timeout: Optional[Duration] = none
    tls: TlsOptions
    compression: Bool
```

