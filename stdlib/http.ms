from "@std/bytes.ms" import Bytes, join
from "@std/net.ms" import Connection
from "@std/net.ms" import DatagramSocket
from "@std/net.ms" import DnsRecord
from "@std/time.ms" import Duration
from "@std/io.ms" import IoError
from "@std/json.ms" import stringify
from "@std/net.ms" import Listener
from "@std/net.ms" import NetworkError
from "@std/io.ms" import ReadStream
from "@std/net.ms" import TlsOptions
from "@std/net.ms" import WebSocket
from "@std/net.ms" import WebSocketError
from "@std/net.ms" import WebSocketOptions

extern def msrt_http_headers_append(
    headers: HttpHeaders,
    name: String,
    value: Bytes
) -> Result[Unit, HttpError]

extern def msrt_http_headers_values(
    value: HttpHeaders,
    name: String
) -> Optional[List[Bytes]]

extern def msrt_http_headers_text(
    value: HttpHeaders,
    name: String
) -> Result[Optional[List[String]], HttpError]

extern def msrt_http_headers_names(value: HttpHeaders) -> List[String]

extern def msrt_http_headers_remove(value: HttpHeaders, name: String) -> Bool

extern def msrt_http_headers_clone(value: HttpHeaders) -> HttpHeaders

extern def msrt_http_headers_new() -> HttpHeaders

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
export extern type HttpHeaders

impl HttpHeaders:
    # Appends raw bytes under a valid HTTP name; invalid names return InvalidInput.
    # Transport operations additionally validate UTF-8, framing and field values.
    def append(name: String, value: Bytes) -> Result[Unit, HttpError]:
        return msrt_http_headers_append(self, name, value)

    # Returns an owned copy of the membership, or none for an absent name.
    def values(name: String) -> Optional[List[Bytes]]:
        return msrt_http_headers_values(self, name)

    # Decodes every value; invalid UTF-8 returns InvalidData without partial success.
    def text(name: String) -> Result[Optional[List[String]], HttpError]:
        return msrt_http_headers_text(self, name)

    # Returns first-inserted spellings in insertion order.
    def names() -> List[String]:
        return msrt_http_headers_names(self)

    # Removes a name; existing list aliases are detached from this header object.
    def remove(name: String) -> Bool:
        return msrt_http_headers_remove(self, name)

    # Copies name/list membership and shares immutable Bytes values.
    def clone() -> HttpHeaders:
        return msrt_http_headers_clone(self)

# Creates empty mutable headers. No header values are joined or comma-combined.
export def headers() -> HttpHeaders:
    return msrt_http_headers_new()

# Response status and headers shared by buffered and streaming response access.
export type HttpResponseMetadata:
    # The received status; editing metadata leaves wire/body behavior unchanged.
    status: Int
    # The header fields, with every repeated value retained.
    headers: HttpHeaders
    # The protocol the response used, such as `HTTP/1.1` or `HTTP/2.0`; empty when the source does not report one.
    protocol: String = ""

# Buffered response body with explicit common metadata access.
export type ClientResponse:
    # Response metadata; changing it requires a mutable response and no live borrow of head.
    head: HttpResponseMetadata
    # The complete response payload within the supplied byte bound.
    body: Bytes

impl ClientResponse:
    # Borrows the current response metadata.
    # Clone the result for an independent owned value, including its headers.
    def metadata() -> ref HttpResponseMetadata:
        return self.head

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

impl HttpMethod:
    # Returns the method token; outgoing requests reject malformed Custom tokens.
    def text() -> String:
        match self:
            case Get: return "GET"
            case Head: return "HEAD"
            case Post: return "POST"
            case Put: return "PUT"
            case Patch: return "PATCH"
            case Delete: return "DELETE"
            case Connect: return "CONNECT"
            case Options: return "OPTIONS"
            case Trace: return "TRACE"
            case Custom(value): return value.clone()

# Reusable HTTP client with connection pooling and explicit response limits.
# Outbound headers retain separate values in their stored order.
export interface HttpClient:
    # Cancels in-flight requests, closes open response bodies, and drops idle pooled connections.
    # Safe to call repeatedly; later requests return Closed.
    def close() -> Unit
    # Sends the UTF-8 text body and returns a scoped streaming response body.
    def request(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: String = "",
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[ResponseBody, HttpError]
    # Sends immutable Bytes and returns a scoped streaming response body.
    def request_bytes(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: Bytes = "".to_bytes(),
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[ResponseBody, HttpError]
    # Borrows ReadStream upload data through the scoped response lifetime.
    def request_stream(
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
    # Largest accepted size of a response header block, in bytes. Must be positive; none uses the default of 1 MiB.
    max_header_bytes: Optional[Int] = none
    # How long an idle pooled connection is kept before it is closed. none never expires it, and a negative duration is rejected.
    idle_timeout: Optional[Duration] = none
    # When True, gzip-encoded responses are decoded transparently, with `max_response_bytes` bounding the decoded size; when False (the default), bodies arrive exactly as sent.
    decompress: Bool = False
    # When True, the client keeps an in-memory cookie jar for its lifetime, respecting public-suffix boundaries; when False (the default), no cookies are stored or sent automatically.
    cookies: Bool = False
    # TLS trust and client-certificate settings for `https` requests. The host name is taken from each URL, so `server_name` is ignored.
    tls: TlsOptions = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "",
        alpn: [], require_client_certificate: False
    )

# One streaming server exchange. Read or write incrementally and close when done.
# Received headers are one shared mutable object; repeated values stay separate.
export interface HttpExchange:
    # Ends the exchange, interrupting reads or writes in progress.
    # Later operations return Closed.
    def close() -> Unit
    # Returns the request headers as shared mutable fields with every repeated value retained.
    def headers() -> HttpHeaders
    # Returns the request method, using the Custom case for extension tokens.
    def method() -> HttpMethod
    # Returns the percent-decoded request path with dot segments resolved.
    # Requests with an encoded slash or NUL are rejected before the handler runs.
    def path() -> String
    # Returns the protocol the request arrived over, such as `HTTP/1.1` or `HTTP/2.0`.
    def protocol() -> String
    # Returns the raw query string without the leading `?`; it is empty when there is none.
    def query() -> String
    # Returns the next chunk of the request body, at most `max_bytes` and never more than 65536, or none at the end of the body.
    # Reading past `max_body_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.
    def read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    # Sends a whole response: the status line, `headers`, and `body` with its length known, so the response carries `Content-Length` rather than chunked framing. Requests with HEAD and statuses without a body get the head alone.
    # The rules of `send_headers` apply, `body` is bounded by `max_response_bytes`, and nothing else may be sent afterwards.
    def send(status: Int, headers: HttpHeaders, body: Bytes) -> Result[Unit, HttpError]
    # Sends the status line and headers once, before any body is written.
    # The status must be 200 through 599, header names cannot be `Content-Length`, `Transfer-Encoding`, or `Connection`, and header bytes are bounded by `max_header_bytes`. A second call returns InvalidInput and a closed exchange returns Closed.
    def send_headers(status: Int, headers: HttpHeaders) -> Result[Unit, HttpError]
    # Switches the connection to a WebSocket after checking the `Origin` header. Requests without an Origin are accepted; otherwise it must exactly match an entry of `allowed_origins`, or, when that list is empty, match the request's own scheme and host.
    # `subprotocols` lists the protocols the server accepts, and `max_message_bytes` must be positive when given. An exchange that already sent headers or upgraded returns InvalidInput, and a request that is not a valid WebSocket upgrade returns Failed.
    def upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Optional[Int] = none
    ) -> Result[WebSocket, WebSocketError]
    # Writes one chunk of the response body and flushes it.
    # `send_headers` must come first, and writing beyond `max_response_bytes` returns IoError.Failed. Responses to HEAD requests and with status 204 or 304 cannot have a body.
    def write(data: String) -> Result[Unit, IoError]
    # Writes one chunk of raw bytes with the same rules as write.
    def write_bytes(data: Bytes) -> Result[Unit, IoError]

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
    # The protocol the request arrived over, such as `HTTP/1.1` or `HTTP/2.0`; empty when not reported.
    protocol: String = ""

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
    def address() -> String
    # Stops accepting connections, waits up to the grace period for in-flight requests, then cancels the rest and waits for them.
    # SIGINT/SIGTERM drains the same way when grace is nonzero: in-flight requests finish within the grace period before the program exits 130/143.
    # Safe to call repeatedly. A request handler calling close on its own server faults, and a shutdown error is raised as a fault.
    def close() -> Unit
    # Blocks until the server stops. Returns Ok after a normal `close`, or IoError.Failed with the host's text if serving ended with an error.
    # Cancelling the waiting task stops the wait.
    def wait() -> Result[Unit, IoError]

# Request and response limits, deadlines, graceful shutdown, and TLS server settings.
export type HttpServerOptions:
    # Most requests handled at once; further requests are answered with 503. Must be positive; none sets no cap.
    max_requests: Optional[Int] = none
    # Largest accepted request body, in bytes. Must be nonnegative; none sets no cap.
    max_body_bytes: Optional[Int] = none
    # Most response body bytes a handler may write, in bytes. Must be nonnegative; none sets no cap.
    max_response_bytes: Optional[Int] = none
    # Largest accepted request header block and largest response header block, in bytes. Must be positive; none uses the default of 1 MiB.
    max_header_bytes: Optional[Int] = none
    # Per-request time budget covering reading the request, running the handler, and writing the response; an idle plain-HTTP connection waiting for its next request is also closed after it. A handler still running at the deadline is cancelled (`tasks.cancelled()` turns true and its waits end) and the request is answered 504; a WebSocket it opened is not limited. Must be positive; none sets no deadline.
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
    def close() -> Unit
    # Returns the response head (status and headers) without copying; it stays available after close.
    def metadata() -> HttpResponseMetadata
    # Returns the next chunk of the response body, at most `max_bytes` and never more than 65536, or none at the end of the body.
    # Reading past the request's `max_response_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.
    def read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    # Reads the rest of the body into one value, with `read`'s limit and error rules.
    # A plain HTTP/1.1 body of known length arrives straight into the result without intermediate copies.
    def read_all() -> Result[Bytes, IoError]

# Maps a stream failure to the HTTP error with the same meaning, so exchange handlers need one error type.
export def from_io(error: IoError) -> HttpError:
    match error:
        case Closed: return HttpError.Closed
        case InvalidInput: return HttpError.InvalidInput
        case InvalidData: return HttpError.InvalidData
        case LimitExceeded: return HttpError.LimitExceeded
        case Unavailable: return HttpError.Failed("HTTP: unavailable")
        case Failed(message): return HttpError.Failed(message.clone())

# Reads the rest of the request body into one value.
# A body over `max_body_bytes` of the server's options returns LimitExceeded; `limit` also bounds it when given.
export def read_body(
    exchange: HttpExchange,
    limit: Optional[Int] = none
) -> Result[Bytes, HttpError]:
    let first = try exchange.read().map_error(from_io)
    if let head = first:
        return read_rest(exchange, head, limit)

    return ok("".to_bytes())

# Joins `head` with the chunks after it. A body that fits one chunk is returned without copying.
def read_rest(
    exchange: HttpExchange,
    head: Bytes,
    limit: Optional[Int]
) -> Result[Bytes, HttpError]:
    var total = head.length()
    if over_limit(total, limit): return error(HttpError.LimitExceeded)

    let second = try exchange.read().map_error(from_io)

    if let next = second:
        total += next.length()
        if over_limit(total, limit): return error(HttpError.LimitExceeded)

        return read_more(exchange, [head, next], total, limit)

    return ok(head)

def read_more(
    exchange: HttpExchange,
    chunks: List[Bytes],
    total: Int,
    limit: Optional[Int]
) -> Result[Bytes, HttpError]:
    var parts = chunks
    var size = total

    while True:
        let chunk = try exchange.read().map_error(from_io)

        if let bytes = chunk:
            size += bytes.length()
            if over_limit(size, limit): return error(HttpError.LimitExceeded)

            parts.append(bytes)
        else:
            return ok(join(parts))

def over_limit(total: Int, limit: Optional[Int]) -> Bool:
    if let max = limit:
        return total > max

    return False

# Sends `response` whole: its status and headers, then its body.
export def reply(
    exchange: HttpExchange,
    response: HttpResponse
) -> Result[Unit, HttpError]:
    return exchange.send(response.status, response.headers, response.body)

# Builds a response with a UTF-8 text body and no headers.
export def text(status: Int, body: String) -> HttpResponse:
    return HttpResponse(status: status, headers: headers(), body: body.to_bytes())

# Builds a response whose body is `value` encoded as JSON, with `Content-Type: application/json`.
# A value `stringify` cannot encode returns Failed with its diagnostic.
export def json[T](status: Int, value: T) -> Result[HttpResponse, HttpError]:
    let body = stringify(value)
    if body.is_error(): return error(HttpError.Failed(body.err().message()))

    let sent = headers()
    try sent.append("Content-Type", "application/json".to_bytes())
    return ok(HttpResponse(status: status, headers: sent, body: body.get().to_bytes()))

# Builds a redirect to `location` with an empty body.
# The status should be 301, 302, 303, 307, or 308; the default 303 sends a followed POST on as a GET.
export def redirect(
    location: String,
    status: Int = 303
) -> Result[HttpResponse, HttpError]:
    let sent = headers()
    try sent.append("Location", location.to_bytes())
    return ok(HttpResponse(status: status, headers: sent, body: "".to_bytes()))

# Adapts a handler that maps a whole request to a whole response into an exchange handler for `serve`.
# The request body is read in full first.
export def buffered(
    handler: Callable[[HttpRequest], HttpResponse]
) -> Callable[[HttpExchange], Result[Unit, HttpError]]:
    return lambda exchange: serve_buffered(handler, exchange)

def serve_buffered(
    handler: Callable[[HttpRequest], HttpResponse],
    exchange: HttpExchange
) -> Result[Unit, HttpError]:
    let body = try read_body(exchange)
    let request = HttpRequest(
        method: exchange.method(), path: exchange.path(), query: exchange.query(),
        headers: exchange.headers(), body: body, protocol: exchange.protocol()
    )
    return reply(exchange, handler(request))

impl Error for HttpError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `HTTP: <reason>`.
    def message() -> String:
        match self:
            case InvalidInput: return "HTTP: invalid input"
            case InvalidData: return "HTTP: invalid data"
            case LimitExceeded: return "HTTP: limit exceeded"
            case PermissionDenied: return "HTTP: permission denied"
            case Closed: return "HTTP: resource is closed"
            case Timeout: return "HTTP: operation timed out"
            case Failed(message): return message.clone()
