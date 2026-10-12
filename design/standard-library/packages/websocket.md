+++
title = "WebSocket sessions"
weight = 57
+++

# WebSocket sessions

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

## `@std/websocket.ms`

## WebSocket operations

```text
fn receive() -> Result[Optional[WebSocketMessage], LibraryError]
fn send(data: Bytes, text: Bool) -> Result[Unit, LibraryError]
fn ping(data: Bytes) -> Result[Unit, LibraryError]
fn subprotocol() -> String
fn close() -> Unit
```

Network.web_socket acquires a client WebSocket for an explicit ws/wss URL, headers, subprotocols and WebSocketOptions. HttpExchange.upgrade acquires the server session inside an admitted request. Both return synchronized shared Closeable views. Wss retains hostname/chain verification, explicit TLS roots/client certificates and destination restrictions.

```text
type WebSocketOptions:
    max_message_bytes: Int
    timeout: Duration
    tls: TlsOptions
    compression: Bool

type WebSocketMessage:
    data: Bytes
    text: Bool
```

Client max_message_bytes and handshake timeout are positive. Client compression is explicit permessage-deflate negotiation; server upgrade currently accepts ordinary uncompressed messages. Bounds apply to decompressed message data as well as wire frames. Receive returns one complete text/binary message or none for normal peer close. Oversized messages return LimitExceeded and terminate transport; invalid text UTF-8 returns InvalidData. Repeated reads after a protocol failure return Closed rather than spinning inside the protocol implementation. Send validates text UTF-8 and bounds outbound message bytes. Ping limits control payloads to 125 bytes.

One reader and one writer may progress concurrently; calls in the same direction serialize. Fragmentation, masking, control frames and close codes follow RFC 6455 through the pinned Gorilla implementation. Subprotocol tokens are validated and the selected protocol is observable. Client callers cannot override Sec-WebSocket handshake/framing headers. Server upgrade accepts absent Origin, and by default same-host origins; an explicit allowed_origins list authorizes exact http/https origins, never a wildcard implicit grant.

The server session remains inside the HTTP request lifetime. Disconnect, request timeout and server/Network shutdown interrupt blocking receives/writes, close the hijacked socket and join the handler's nested work. Close is idempotent, attempts a normal close control frame with a short bounded write deadline, then releases the handle and joins admitted operations. Source must not retain a session as detached work outside the request. Client sessions remain owned by their Network and lexical with scope. HTTP/3 is unrelated to the supported WebSocket transport and is excluded from this expansion by user request.

```text
fn web_socket(url: String, headers: Map[String, String], subprotocols: List[String], options: WebSocketOptions) -> Result[WebSocket&Shareable, LibraryError]
```
