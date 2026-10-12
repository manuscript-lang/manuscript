+++
title = "WebSocket sessions"
weight = 57
+++

# WebSocket sessions

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

A WebSocket session sends and receives complete text or binary messages over a connection. Client sessions come from Network; server sessions come from an HTTP upgrade. Keep each session inside its cleanup and host lifetime.

## `@std/websocket.ms`

## WebSocket operations

```manuscript
fn receive() -> Result[Optional[WebSocketMessage], WebSocketError]
fn send(data: Bytes, text: Bool) -> Result[Unit, WebSocketError]
fn ping(data: Bytes) -> Result[Unit, WebSocketError]
fn subprotocol() -> String
fn close() -> Unit
```

## Acquiring a session

Network.web_socket acquires a client WebSocket for an explicit ws/wss URL, headers, subprotocols and WebSocketOptions. HttpExchange.upgrade acquires the server session inside an admitted request. Both return contract views with synchronized operations and explicit close. Wss retains hostname/chain verification, explicit TLS roots/client certificates and destination restrictions.

```manuscript
type WebSocketOptions:
    max_message_bytes: Optional[Int]
    timeout: Optional[Duration]
    tls: TlsOptions
    compression: Bool

type WebSocketMessage:
    data: Bytes
    text: Bool
```

## Message limits and errors

Client message caps and handshake deadlines are optional. Supplied message caps must be positive and supplied deadlines nonnegative; zero expires immediately. Clients negotiate permessage-deflate only when compression is explicitly enabled. Server upgrade currently accepts uncompressed messages. Bounds apply to decompressed message data as well as wire frames. `receive` returns one complete text or binary message, or `none` when the peer closes normally. Oversized messages return LimitExceeded and terminate transport; invalid text UTF-8 returns InvalidData. Repeated reads after a protocol failure return Closed rather than spinning inside the protocol implementation. Send validates text UTF-8 and bounds outbound message bytes. Ping limits control payloads to 125 bytes.

## Concurrent calls and protocol rules

One read and one write can run concurrently. Two reads, or two writes, are serialized. Fragmentation, masking, control frames and close codes follow RFC 6455 through the pinned Gorilla implementation. Subprotocol tokens are validated and the selected protocol is observable. Client callers cannot override Sec-WebSocket handshake/framing headers. Server upgrade accepts absent Origin, and by default same-host origins; an explicit allowed_origins list authorizes exact http/https origins, never a wildcard implicit grant.

## Session lifetime

The server session remains inside the HTTP request lifetime. Disconnect, request timeout and server/Network shutdown interrupt blocking receives/writes, close the hijacked socket and join the handler's nested work. Close is idempotent, attempts a normal close control frame with a short bounded write deadline, then releases the handle and joins admitted operations. Source must not retain a session as detached work outside the request. Client sessions remain owned by their Network and lexical with scope. HTTP/3 is unrelated to the supported WebSocket transport and is excluded from this expansion by user request.

```manuscript
fn web_socket(url: String, headers: Map[String, String], subprotocols: List[String], options: WebSocketOptions) -> Result[WebSocket, WebSocketError]
```
