+++
title = "websocket"
+++

# @std/websocket.ms

Import each required symbol with `import Name from "@std/websocket.ms"`.

## WebSocket {data-api-kind="Interface"}

```manuscript
interface WebSocket:
    fn close() -> Unit
    fn ping(data: Bytes) -> Result[Unit, LibraryError]
    fn receive() -> Result[Optional[WebSocketMessage], LibraryError]
    fn send(data: Bytes, text: Bool) -> Result[Unit, LibraryError]
    fn subprotocol() -> String
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
    max_message_bytes: Int
    timeout: Duration
    tls: TlsOptions
    compression: Bool
```

