+++
title = "websocket"
+++

# @std/websocket.ms

Import each required symbol with `import Name from "@std/websocket.ms"`.

## WebSocket

Kind: interface.

```text
WebSocket: WebSocket
operation close: fn()->Unit
operation ping: fn(data: Bytes)->Result[Unit, LibraryError]
operation receive: fn()->Result[Optional[WebSocketMessage], LibraryError]
operation send: fn(data: Bytes, text: Bool)->Result[Unit, LibraryError]
operation subprotocol: fn()->String
```

## WebSocketMessage

Kind: record.

```text
WebSocketMessage: WebSocketMessage
field data: Bytes
field text: Bool
```

## WebSocketOptions

Kind: record.

```text
WebSocketOptions: WebSocketOptions
field max_message_bytes: Int
field timeout: Duration
field tls: TlsOptions
field compression: Bool
```

