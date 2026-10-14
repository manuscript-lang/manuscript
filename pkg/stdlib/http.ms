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
    # The URL is not an `http` or `https` URL with a host, valid port, and no user info; a method, header name, or value is malformed or host-managed; or a limit or timeout is negative.
    case InvalidInput
    # The response headers are not valid UTF-8, so they cannot become Strings.
    case InvalidData
    # A buffered response body is larger than `max_response_bytes`.
    case LimitExceeded
    # The network's restrictions disallow the host, a resolved address, or a redirect destination.
    case PermissionDenied
    # The client or network was closed before or during the request.
    case Closed
    # The request timeout elapsed before the response completed.
    case Timeout
    # Transport, TLS, or protocol failure reported by the host, such as a refused connection or an exceeded redirect limit.
    case Failed(
        # Host-provided failure text; `message()` returns it verbatim, so it can name addresses.
        message: String
    )

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
    # Asks which communication options the target supports, without transferring a body.
    case Options
    # Requests a diagnostic loopback.
    case Trace
    # Carries an extension token; requests reject empty or malformed tokens.
    case Custom(
        # The method token; it must be a non-empty HTTP token such as PURGE.
        value: String
    )
    # Returns the method token; outgoing requests reject malformed Custom tokens.
    fn text() -> String:

# Reusable HTTP client with connection pooling and explicit response limits.
# Outbound headers retain separate values in their stored order.
export interface HttpClient:
    # Cancels in-flight requests, closes open response bodies, and drops idle pooled connections.
    # Safe to call repeatedly; later requests return Closed.
    fn close() -> Unit
    # Sends immutable Bytes and returns a scoped streaming response body.
    fn request(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: Bytes = "".to_bytes(),
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
    # Most redirects followed per request. 0 returns the redirect response itself, none sets no cap, and a negative count is rejected.
    # Redirects that downgrade from HTTPS, leave the network's restrictions, or carry user info are refused.
    max_redirects: Optional[Int] = none
    # Number of idle connections kept for reuse. Must be nonnegative; none sets no explicit cap.
    max_idle_connections: Optional[Int] = none
    # Largest accepted size of a response header block, in bytes. Must be positive; none sets no cap.
    max_header_bytes: Optional[Int] = none
    # How long an idle pooled connection is kept before it is closed. none never expires it, and a negative duration is rejected.
    idle_timeout: Optional[Duration] = none
    # When true, gzip-encoded responses are decoded transparently, with `max_response_bytes` bounding the decoded size; when false (the default), bodies arrive exactly as sent.
    decompress: Bool = false
    # When true, the client keeps an in-memory cookie jar for its lifetime, respecting public-suffix boundaries; when false (the default), no cookies are stored or sent automatically.
    cookies: Bool = false
    # TLS trust and client-certificate settings for `https` requests. The host name is taken from each URL, so `server_name` is ignored.
    tls: TlsOptions = TlsOptions(
        server_name: "",
        roots_pem: "",
        certificate_pem: "",
        private_key_pem: "",
        alpn: [],
        require_client_certificate: false
    )

# One streaming server exchange. Read or write incrementally and close when done.
# Received headers are one shared mutable object; repeated values stay separate.
export interface HttpExchange:
    # Ends the exchange, interrupting reads or writes in progress.
    # Later operations return Closed.
    fn close() -> Unit
    # Returns the request headers as shared mutable fields with every repeated value retained.
    fn headers() -> HttpHeaders
    # Returns the request method, using the Custom case for extension tokens.
    fn method() -> HttpMethod
    # Returns the percent-decoded request path with dot segments resolved.
    # Requests with an encoded slash or NUL are rejected before the handler runs.
    fn path() -> String
    # Returns the raw query string without the leading `?`; it is empty when there is none.
    fn query() -> String
    # Returns the next chunk of the request body, at most `max_bytes` and never more than 65536, or none at the end of the body.
    # Reading past `max_body_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    # Sends the status line and headers once, before any body is written.
    # The status must be 200 through 599, header names cannot be `Content-Length`, `Transfer-Encoding`, or `Connection`, and header bytes are bounded by `max_header_bytes`. A second call returns InvalidInput and a closed exchange returns Closed.
    fn send_headers(
        status: Int,
        headers: HttpHeaders
    ) -> Result[Unit, HttpError]
    # Switches the connection to a WebSocket after checking the `Origin` header. Requests without an Origin are accepted; otherwise it must exactly match an entry of `allowed_origins`, or, when that list is empty, match the request's own scheme and host.
    # `subprotocols` lists the protocols the server accepts, and `max_message_bytes` must be positive when given. An exchange that already sent headers or upgraded returns InvalidInput, and a request that is not a valid WebSocket upgrade returns Failed.
    fn upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Optional[Int] = none
    ) -> Result[WebSocket, WebSocketError]
    # Writes one chunk of the response body and flushes it.
    # `send_headers` must come first, and writing beyond `max_response_bytes` returns IoError.Failed. Responses to HEAD requests and with status 204 or 304 cannot have a body.
    fn write(data: Bytes) -> Result[Unit, IoError]

# Buffered request accepted by the simple HTTP server handler.
export type HttpRequest:
    # The request method, using the Custom case for extension tokens.
    method: HttpMethod
    # The percent-decoded request path with dot segments resolved, so `/a/../b` arrives as `/b`.
    path: String
    # The raw query string without the leading `?`; empty when there is none.
    query: String
    # The request headers as mutable fields with every repeated value retained.
    headers: HttpHeaders
    # The complete request body, at most `max_body_bytes` long.
    body: Bytes

# Buffered response returned by the simple HTTP server handler.
export type HttpResponse:
    # The HTTP status code, which must be 200 through 599; other values are answered with a 500 error.
    status: Int
    # The response headers to send; `Content-Length`, `Transfer-Encoding`, and `Connection` are rejected with a 500 error.
    headers: HttpHeaders
    # The response body bytes, which must not exceed `max_response_bytes`; the server sets the content length.
    body: Bytes

# A running HTTP server. Close it to stop accepting new requests.
export interface HttpServer:
    # Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.
    fn address() -> String
    # Stops accepting connections, waits up to the grace period for in-flight requests, then cancels the rest and waits for them.
    # Safe to call repeatedly. A request handler calling close on its own server faults, and a shutdown error is raised as a fault.
    fn close() -> Unit
    # Blocks until the server stops. Returns Ok after a normal `close`, or IoError.Failed with the host's text if serving ended with an error.
    # Cancelling the waiting task stops the wait.
    fn wait() -> Result[Unit, IoError]

# Request and response limits, deadlines, graceful shutdown, and TLS server settings.
export type HttpServerOptions:
    # Most requests handled at once; further requests are answered with 503. Must be positive; none sets no cap.
    max_requests: Optional[Int] = none
    # Largest accepted request body, in bytes. Must be nonnegative; none sets no cap.
    max_body_bytes: Optional[Int] = none
    # Most response body bytes a handler may write, in bytes. Must be nonnegative; none sets no cap.
    max_response_bytes: Optional[Int] = none
    # Largest accepted request header block and largest response header block, in bytes. Must be positive; none sets no cap.
    max_header_bytes: Optional[Int] = none
    # Per-request time budget covering reading the request, running the handler, and writing the response. none sets no deadline.
    timeout: Optional[Duration] = none
    # How long `close` waits for in-flight requests to finish before cancelling them. none waits without limit and 0 cancels immediately.
    grace: Optional[Duration] = none
    # Some(options) serves HTTPS and negotiates HTTP/2 or HTTP/1.1 through ALPN; none, the default, serves plain HTTP/1.1.
    tls: Optional[TlsOptions] = none

# Streaming response body returned by reusable HTTP client operations.
# Metadata remains available after close and shares one mutable header object.
export interface ResponseBody:
    # Cancels the rest of the response and releases its connection.
    # Safe to call repeatedly; reads afterwards return Closed. A fully read body lets the connection be reused.
    fn close() -> Unit
    # Returns the response head (status and headers) without copying; it stays available after close.
    fn metadata() -> HttpResponseMetadata
    # Returns the next chunk of the response body, at most `max_bytes` and never more than 65536, or none at the end of the body.
    # Reading past the request's `max_response_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]

impl Error for HttpError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `HTTP: <reason>`.
    fn message() -> String:
