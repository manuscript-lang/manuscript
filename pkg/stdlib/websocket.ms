# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import TlsOptions from "@std/tls.ms"

# Errors returned by WebSocket handshakes, message limits, timeouts, or closed sockets.
export type WebSocketError:
    # A URL is not a `ws` or `wss` URL with a host and no user info, `max_message_bytes` is not positive, a header, subprotocol, or option is malformed, or a ping payload exceeds 125 bytes.
    case InvalidInput
    # A text message is not valid UTF-8, whether being sent or received.
    case InvalidData
    # A message is larger than `max_message_bytes`.
    case LimitExceeded
    # The network handle's restriction policy does not allow the host.
    case PermissionDenied
    # The socket or its network handle was closed, or an earlier read failure already ended the connection.
    case Closed
    # The connection attempt did not finish within `timeout`.
    case Timeout
    # Handshake, transport, or protocol failure, such as a refused connection or a rejected upgrade.
    case Failed(
        # Host-provided failure text; `message()` returns it verbatim, so it can name addresses.
        message: String
    )

# A WebSocket connection. Send and receive byte messages with an explicit text flag.
export interface WebSocket:
    # Sends a normal-closure frame, waiting at most about 100 ms to write it, then closes the connection and waits for in-flight calls to stop.
    # Safe to call repeatedly; later calls wait for the first.
    fn close() -> Unit
    # Sends a ping frame carrying `data`, which must be at most 125 bytes, with a one-second write deadline.
    # It does not wait for the pong. Returns Closed on a closed socket.
    fn ping(data: Bytes) -> Result[Unit, WebSocketError]
    # Waits for the next complete message and returns it, or none once the peer closes normally.
    # A larger message returns LimitExceeded and a malformed text message InvalidData; after any receive failure the connection is closed. One receive runs at a time, and others wait their turn.
    fn receive() -> Result[Optional[WebSocketMessage], WebSocketError]
    # Sends `data` as one message, a text frame when `text` is true and a binary frame otherwise.
    # Text must be valid UTF-8 or the call returns InvalidData, and a payload over `max_message_bytes` returns LimitExceeded. One send runs at a time.
    fn send(data: Bytes, text: Bool) -> Result[Unit, WebSocketError]
    # Returns the subprotocol the server selected during the handshake, or an empty string when none was negotiated.
    get subprotocol -> String

# A received message and whether its payload is UTF-8 text.
export type WebSocketMessage:
    # The message payload bytes; for a text message they are the UTF-8 encoding of the text.
    data: Bytes
    # True when the peer sent a text frame, which guarantees `data` is valid UTF-8; false for a binary frame.
    text: Bool

# WebSocket message, timeout, TLS, and per-message compression settings.
export type WebSocketOptions:
    # Largest message accepted or sent, in bytes. Must be positive; none sets no limit.
    max_message_bytes: Optional[Int] = none
    # Time budget for connecting and completing the opening handshake. none waits indefinitely and a negative duration is rejected.
    timeout: Optional[Duration] = none
    # TLS settings for `wss` URLs: trusted roots, client identity, and protocols.
    tls: TlsOptions
    # When true, offers per-message compression during the handshake; it applies only if the peer agrees.
    compression: Bool

impl Error for WebSocketError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `WebSocket: <reason>`.
    fn message() -> String:

# documentation documentation/standard-library/websocket.md
# +++
# title = "WebSockets"
# weight = 17
# +++
#
# # WebSockets
#
# API reference: [websocket](reference/websocket.md).
#
# A WebSocket session sends and receives complete text or binary messages over a connection. Client sessions come from Network; server sessions come from an HTTP upgrade. Keep each session inside its cleanup and host lifetime.
#
# ## Acquiring a session
#
# Network.web_socket acquires a client WebSocket for an explicit ws/wss URL, headers, subprotocols and WebSocketOptions. HttpExchange.upgrade acquires the server session inside an admitted request. Both return contract views with synchronized operations and explicit close. Wss retains hostname/chain verification, explicit TLS roots/client certificates and destination restrictions.
#
# ## Message limits and errors
#
# Client message caps and handshake deadlines are optional. Supplied message caps must be positive and supplied deadlines nonnegative; zero expires immediately. Clients negotiate permessage-deflate only when compression is explicitly enabled. Server upgrade currently accepts uncompressed messages. Bounds apply to decompressed message data as well as wire frames. `receive` returns one complete text or binary message, or `none` when the peer closes normally. Oversized messages return LimitExceeded and terminate transport; invalid text UTF-8 returns InvalidData. Repeated reads after a protocol failure return Closed rather than spinning inside the protocol implementation. Send validates text UTF-8 and bounds outbound message bytes. Ping limits control payloads to 125 bytes.
#
# ## Concurrent calls and protocol rules
#
# One read and one write can run concurrently. Two reads, or two writes, are serialized. Fragmentation, masking, control frames and close codes follow RFC 6455 through the pinned Gorilla implementation. Subprotocol tokens are validated and the selected protocol is observable. Client callers cannot override Sec-WebSocket handshake/framing headers. Server upgrade accepts absent Origin, and by default same-host origins; an explicit allowed_origins list authorizes exact http/https origins, never a wildcard implicit grant.
#
# ## Session lifetime
#
# The server session remains inside the HTTP request lifetime. Disconnect, request timeout and server/Network shutdown interrupt blocking receives/writes, close the hijacked socket and join the handler's nested work. Close is idempotent, attempts a normal close control frame with a short bounded write deadline, then releases the handle and joins admitted operations. Source must not retain a session as detached work outside the request. Client sessions remain owned by their Network and lexical with scope. HTTP/3 is unrelated to the supported WebSocket transport and is excluded from this expansion by user request.
#
# ```manuscript
# fn web_socket(url: String, headers: HttpHeaders, subprotocols: List[String], options: WebSocketOptions) -> Result[WebSocket, WebSocketError]
# ```
# end-documentation
