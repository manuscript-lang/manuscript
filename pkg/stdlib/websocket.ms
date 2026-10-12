# Canonical standard-library declarations. Implementations are native.

import Error from "@std/errors.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import TlsOptions from "@std/tls.ms"

export type WebSocketError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case PermissionDenied
    case Closed
    case Timeout
    case Failed(message: String)

export interface WebSocket:
    fn close() -> Unit
    fn ping(data: Bytes) -> Result[Unit, WebSocketError]
    fn receive() -> Result[Optional[WebSocketMessage], WebSocketError]
    fn send(data: Bytes, text: Bool) -> Result[Unit, WebSocketError]
    fn subprotocol() -> String

export type WebSocketMessage:
    data: Bytes
    text: Bool

export type WebSocketOptions:
    max_message_bytes: Int
    timeout: Duration
    tls: TlsOptions
    compression: Bool

impl Error for WebSocketError:
    fn message() -> String
