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

### WebSocket.close

Sends a normal-closure frame, waiting at most about 100 ms to write it, then closes the connection and waits for in-flight calls to stop.
Safe to call repeatedly; later calls wait for the first.

```manuscript
fn close() -> Unit
```

### WebSocket.ping

Sends a ping frame carrying `data`, which must be at most 125 bytes, with a one-second write deadline.
It does not wait for the pong. Returns Closed on a closed socket.

```manuscript
fn ping(data: Bytes) -> Result[Unit, WebSocketError]
```

### WebSocket.receive

Waits for the next complete message and returns it, or none once the peer closes normally.
A larger message returns LimitExceeded and a malformed text message InvalidData; after any receive failure the connection is closed. One receive runs at a time, and others wait their turn.

```manuscript
fn receive() -> Result[Optional[WebSocketMessage], WebSocketError]
```

### WebSocket.send

Sends `data` as one message, a text frame when `text` is true and a binary frame otherwise.
Text must be valid UTF-8 or the call returns InvalidData, and a payload over `max_message_bytes` returns LimitExceeded. One send runs at a time.

```manuscript
fn send(data: Bytes, text: Bool) -> Result[Unit, WebSocketError]
```

### WebSocket.subprotocol

Returns the subprotocol the server selected during the handshake, or an empty string when none was negotiated.

```manuscript
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

### WebSocketError.Closed

The socket or its network handle was closed, or an earlier read failure already ended the connection.

```manuscript
case Closed
```

### WebSocketError.Failed

Handshake, transport, or protocol failure, such as a refused connection or a rejected upgrade.

```manuscript
case Failed(message: String)
```

### WebSocketError.InvalidData

A text message is not valid UTF-8, whether being sent or received.

```manuscript
case InvalidData
```

### WebSocketError.InvalidInput

A URL is not a `ws` or `wss` URL with a host and no user info, `max_message_bytes` is not positive, a header, subprotocol, or option is malformed, or a ping payload exceeds 125 bytes.

```manuscript
case InvalidInput
```

### WebSocketError.LimitExceeded

A message is larger than `max_message_bytes`.

```manuscript
case LimitExceeded
```

### WebSocketError.PermissionDenied

The network handle's restriction policy does not allow the host.

```manuscript
case PermissionDenied
```

### WebSocketError.Timeout

The connection attempt did not finish within `timeout`.

```manuscript
case Timeout
```

### WebSocketError.Failed.message

Host-provided failure text; `message()` returns it verbatim, so it can name addresses.

```manuscript
message: String
```

### WebSocketError.Error.message

Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `WebSocket: <reason>`.

```manuscript
fn message() -> String:
```

## WebSocketMessage {data-api-kind="Record"}

A received message and whether its payload is UTF-8 text.

```manuscript
type WebSocketMessage:
    data: Bytes
    text: Bool
```

### WebSocketMessage.data

The message payload bytes; for a text message they are the UTF-8 encoding of the text.

```manuscript
data: Bytes
```

### WebSocketMessage.text

True when the peer sent a text frame, which guarantees `data` is valid UTF-8; false for a binary frame.

```manuscript
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

### WebSocketOptions.compression

When true, offers per-message compression during the handshake; it applies only if the peer agrees.

```manuscript
compression: Bool
```

### WebSocketOptions.max_message_bytes

Largest message accepted or sent, in bytes. Must be positive; none sets no limit.

```manuscript
max_message_bytes: Optional[Int] = none
```

### WebSocketOptions.timeout

Time budget for connecting and completing the opening handshake. none waits indefinitely and a negative duration is rejected.

```manuscript
timeout: Optional[Duration] = none
```

### WebSocketOptions.tls

TLS settings for `wss` URLs: trusted roots, client identity, and protocols.

```manuscript
tls: TlsOptions
```

