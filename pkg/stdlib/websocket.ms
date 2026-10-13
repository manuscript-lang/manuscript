# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import TlsOptions from "@std/tls.ms"

# Errors returned by WebSocket handshakes, message limits, timeouts, or closed sockets.
export type WebSocketError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case PermissionDenied
    case Closed
    case Timeout
    case Failed(message: String)

# A WebSocket connection. Send and receive byte messages with an explicit text flag.
export interface WebSocket:
    fn close() -> Unit
    fn ping(data: Bytes) -> Result[Unit, WebSocketError]
    fn receive() -> Result[Optional[WebSocketMessage], WebSocketError]
    fn send(data: Bytes, text: Bool) -> Result[Unit, WebSocketError]
    fn subprotocol() -> String

# A received message and whether its payload is UTF-8 text.
export type WebSocketMessage:
    data: Bytes
    text: Bool

# WebSocket message, timeout, TLS, and per-message compression settings.
export type WebSocketOptions:
    max_message_bytes: Optional[Int64] = none
    timeout: Optional[Duration] = none
    tls: TlsOptions
    compression: Bool

impl Error for WebSocketError:
    fn message() -> String:
