# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import LibraryError from "@std/errors.ms"
import Optional from "@std/optional.ms"
import Result from "@std/result.ms"
import TlsOptions from "@std/tls.ms"

export interface WebSocket:
    fn close() -> Unit
    fn ping(data: Bytes) -> Result[Unit, LibraryError]
    fn receive() -> Result[Optional[WebSocketMessage], LibraryError]
    fn send(data: Bytes, text: Bool) -> Result[Unit, LibraryError]
    fn subprotocol() -> String

export type WebSocketMessage:
    data: Bytes
    text: Bool

export type WebSocketOptions:
    max_message_bytes: Int
    timeout: Duration
    tls: TlsOptions
    compression: Bool
