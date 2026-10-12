+++
title = "websocket"
+++

# @std/websocket.ms

Import each required symbol with `import Name from "@std/websocket.ms"`.

## WebSocket {data-api-kind="Interface"}

```manuscript
interface WebSocket:
    fn close() -> Unit
    fn ping(data: Bytes) -> Result[Unit, WebSocketError]
    fn receive() -> Result[Optional[WebSocketMessage], WebSocketError]
    fn send(data: Bytes, text: Bool) -> Result[Unit, WebSocketError]
    fn subprotocol() -> String
```

## WebSocketError {data-api-kind="Alternative"}

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
    fn message() -> String
```

## WebSocketMessage {data-api-kind="Record"}

```manuscript
type WebSocketMessage:
    data: Bytes
    text: Bool
```

## WebSocketOptions {data-api-kind="Record"}

```manuscript
type WebSocketOptions:
    max_message_bytes: Optional[Int] = none
    timeout: Optional[Duration] = none
    tls: TlsOptions
    compression: Bool
```

