# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Connection from "@std/net.ms"
import DatagramSocket from "@std/net.ms"
import DnsRecord from "@std/net.ms"
import Duration from "@std/time.ms"
import IoError from "@std/io.ms"
import List from "@std/collections.ms"
import Listener from "@std/net.ms"
import Map from "@std/collections.ms"
import NetworkError from "@std/net.ms"
import ReadStream from "@std/io.ms"
import TlsOptions from "@std/tls.ms"
import WebSocket from "@std/websocket.ms"
import WebSocketError from "@std/websocket.ms"
import WebSocketOptions from "@std/websocket.ms"

# Errors returned for invalid requests, transport failures, timeouts, and limits.
export type HttpError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case PermissionDenied
    case Closed
    case Timeout
    case Failed(message: String)

# Buffered HTTP response metadata and body.
export type ClientResponse:
    status: Int
    headers: Map[String, List[String]]
    body: Bytes

# Reusable HTTP client with connection pooling and explicit response limits.
export interface HttpClient:
    fn close() -> Unit
    fn send(
        method: String,
        url: String,
        headers: Map[String, String],
        body: Bytes,
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[ResponseBody, HttpError]
    fn send_stream(
        method: String,
        url: String,
        headers: Map[String, String],
        body: ReadStream,
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[ResponseBody, HttpError]

# Connection, redirect, cookie, decompression, and TLS settings for an HTTP client.
export type HttpClientOptions:
    max_redirects: Optional[Int] = none
    max_idle_connections: Optional[Int] = none
    max_header_bytes: Optional[Int] = none
    idle_timeout: Optional[Duration] = none
    decompress: Bool
    cookies: Bool
    tls: TlsOptions

# One streaming server exchange. Read or write incrementally and close when done.
export interface HttpExchange:
    fn close() -> Unit
    fn headers() -> Map[String, List[String]]
    fn method() -> String
    fn path() -> String
    fn query() -> String
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    fn send_headers(
        status: Int,
        headers: Map[String, List[String]]
    ) -> Result[Unit, HttpError]
    fn upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Optional[Int] = none
    ) -> Result[WebSocket, WebSocketError]
    fn write(data: Bytes) -> Result[Unit, IoError]

# Buffered request accepted by the simple HTTP server handler.
export type HttpRequest:
    method: String
    path: String
    query: String
    headers: Map[String, Bytes]
    body: Bytes
    # Finds a header using ASCII case-insensitive names, or returns `none`.
    # Leaves Map keys unchanged. Repeated received values remain newline-joined bytes.
    # If a manually built Map has equivalent names, returns its first matching entry.
    fn header(name: String) -> Optional[Bytes]:

# Buffered response returned by the simple HTTP server handler.
export type HttpResponse:
    status: Int
    headers: Map[String, String]
    body: Bytes

# A running HTTP server. Close it to stop accepting new requests.
export interface HttpServer:
    fn address() -> String
    fn close() -> Unit
    fn wait() -> Result[Unit, IoError]

# Request and response limits, deadlines, graceful shutdown, and TLS server settings.
export type HttpServerOptions:
    max_requests: Optional[Int] = none
    max_body_bytes: Optional[Int] = none
    max_response_bytes: Optional[Int] = none
    max_header_bytes: Optional[Int] = none
    timeout: Optional[Duration] = none
    grace: Optional[Duration] = none
    tls: Optional[TlsOptions]

# Streaming response body returned by HTTP client operations.
export interface ResponseBody:
    fn close() -> Unit
    fn headers() -> Map[String, List[String]]
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    fn status() -> Int

impl Error for HttpError:
    fn message() -> String:
