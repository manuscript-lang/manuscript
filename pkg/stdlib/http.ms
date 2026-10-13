# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Connection from "@std/net.ms"
import DatagramSocket from "@std/net.ms"
import DnsRecord from "@std/net.ms"
import Duration from "@std/time.ms"
import IoError from "@std/io.ms"
import List from "@std/collections.ms"
import Listener from "@std/net.ms"
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

# Mutable HTTP fields with ASCII case-insensitive names and separate byte values.
# Names keep first-insertion order and spelling; values keep append order.
# Lookup shares list membership. Use clone() to separate mutable membership.
export type HttpHeaders:
    # Appends raw bytes under a valid HTTP name; invalid names return InvalidInput.
    # Transport operations additionally validate UTF-8, framing and field values.
    fn append(name: String, value: Bytes) -> Result[Unit, HttpError]:
    # Returns shared mutable membership, or none for an absent name.
    fn values(name: String) -> Optional[List[Bytes]]:
    # Decodes every value; invalid UTF-8 returns InvalidData without partial success.
    fn text(name: String) -> Result[Optional[List[String]], HttpError]:
    # Returns first-inserted spellings in insertion order.
    fn names() -> List[String]:
    # Removes a name; existing list aliases are detached from this header object.
    fn remove(name: String) -> Bool:
    # Copies name/list membership and shares immutable Bytes values.
    fn clone() -> HttpHeaders:

# Creates empty mutable headers. No header values are joined or comma-combined.
export fn headers() -> HttpHeaders:

# Response status and headers shared by buffered and streaming response access.
export type HttpResponseMetadata:
    # The received status; editing metadata leaves wire/body behavior unchanged.
    status: Int
    # The shared mutable fields, with every repeated value retained.
    headers: HttpHeaders

# Buffered response body with explicit common metadata access.
export type ClientResponse:
    # Current mutable metadata; replacing head detaches existing metadata aliases.
    head: HttpResponseMetadata
    # The complete response payload within the supplied byte bound.
    body: Bytes
    # Returns current head without copying; record clone is shallow.
    # Clone headers explicitly when separate mutable membership is needed.
    fn metadata() -> HttpResponseMetadata:

# Known HTTP methods, plus extension tokens validated by outgoing operations.
export type HttpMethod:
    # Requests the selected representation.
    case Get
    # Requests response metadata without a body.
    case Head
    # Submits a representation for processing.
    case Post
    # Replaces the selected representation.
    case Put
    # Applies a partial modification.
    case Patch
    # Removes the selected representation.
    case Delete
    # Establishes a tunnel to the request target.
    case Connect
    # Requests communication options.
    case Options
    # Requests a diagnostic loopback.
    case Trace
    # Carries an extension token; requests reject empty or malformed tokens.
    case Custom(value: String)
    # Returns the method token; outgoing requests reject malformed Custom tokens.
    fn text() -> String:

# Reusable HTTP client with connection pooling and explicit response limits.
# Outbound headers retain separate values in their stored order.
export interface HttpClient:
    fn close() -> Unit
    # Sends immutable Bytes and returns a scoped streaming response body.
    fn request(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: Bytes,
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[ResponseBody, HttpError]
    # Borrows ReadStream upload data through the scoped response lifetime.
    fn request_stream(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
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
# Received headers are one shared mutable object; repeated values stay separate.
export interface HttpExchange:
    fn close() -> Unit
    fn headers() -> HttpHeaders
    fn method() -> HttpMethod
    fn path() -> String
    fn query() -> String
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    fn send_headers(
        status: Int,
        headers: HttpHeaders
    ) -> Result[Unit, HttpError]
    fn upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Optional[Int] = none
    ) -> Result[WebSocket, WebSocketError]
    fn write(data: Bytes) -> Result[Unit, IoError]

# Buffered request accepted by the simple HTTP server handler.
export type HttpRequest:
    method: HttpMethod
    path: String
    query: String
    headers: HttpHeaders
    body: Bytes

# Buffered response returned by the simple HTTP server handler.
export type HttpResponse:
    status: Int
    headers: HttpHeaders
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

# Streaming response body returned by reusable HTTP client operations.
# Metadata remains available after close and shares one mutable header object.
export interface ResponseBody:
    fn close() -> Unit
    fn metadata() -> HttpResponseMetadata
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]

impl Error for HttpError:
    fn message() -> String:
