from "@std/sync.ms" import lock
from "@std/net.ms" import network, QueryEntry, parse_query
from "@std/io.ms" import WriteStream, read_all
from "@std/streams.ms" import from_bytes
from "@std/json.ms" import stringify, parse, JsonError, JsonLimits, JsonValue
from "@std/net.ms" import Network, IpAddress, Cidr, parse_ip, contains_ip
from "@std/tasks.ms" import TaskGroup
from "@std/collections.ms" import range
from "@std/time.ms" import Instant, clock
from "@std/shared.ms" import Shared, share
from "@std/core.ms" import panic, Closeable
from "@std/bytes.ms" import Bytes
from "@std/net.ms" import Connection
from "@std/net.ms" import DatagramSocket
from "@std/net.ms" import DnsRecord
from "@std/time.ms" import Duration
from "@std/io.ms" import IoError
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
    # Largest accepted size of a response header block, in bytes. Must be positive; none sets no cap.
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
    # Sets an optional access-event route label, capped at 2048 bytes; excludes request-specific captures.
    def set_route(route: String) -> Unit
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
    # Direct transport peer as host:port; forwarded headers are never trusted implicitly.
    def peer_address() -> String
    # Transport scheme, http or https, determined by the accepted connection.
    def scheme() -> String
    # Returns the raw query string without the leading `?`; it is empty when there is none.
    def query() -> String
    # Returns the next chunk of the request body, at most `max_bytes` and never more than 65536, or none at the end of the body.
    # Reading past `max_body_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.
    def read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    # Sends the status line and headers once, before any body is written.
    # The status must be 200 through 599, header names cannot be `Content-Length`, `Transfer-Encoding`, or `Connection`, and header bytes are bounded by `max_header_bytes`. A second call returns InvalidInput and a closed exchange returns Closed.
    # An optional length selects fixed framing and enforces ordinary response totals; HEAD/304 describe the representation without sending it. 204 forbids a length and 205 allows only zero.
    def send_headers(
        status: Int,
        headers: HttpHeaders,
        content_length: Optional[Int] = none
    ) -> Result[Unit, HttpError]
    # Switches the connection to a WebSocket after checking the `Origin` header. Requests without an Origin are accepted; otherwise it must exactly match an entry of `allowed_origins`, or, when that list is empty, match the request's own scheme and host.
    # `subprotocols` lists the protocols the server accepts, and `max_message_bytes` must be positive when given. An exchange that already sent headers or upgraded returns InvalidInput, and a request that is not a valid WebSocket upgrade returns Failed.
    def upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Optional[Int] = none
    ) -> Result[WebSocket, WebSocketError]
    # Upgrades with additional response fields, preserving repeated cookies. Framing,
    # Upgrade, and Sec-WebSocket-* fields are host-managed; invalid fields return
    # InvalidInput. The entire handshake is bounded by max_header_bytes before commitment.
    def upgrade_with_headers(
        allowed_origins: List[String],
        subprotocols: List[String],
        response_headers: HttpHeaders,
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
    # Direct transport peer as host:port; empty for synthetic requests.
    peer_address: String = ""
    # Transport scheme, http or https; forwarded headers do not override it.
    scheme: String = ""

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
    # Returns independent, saturating counters for this member.
    def stats() -> HttpStats
    # True after activation and before drain begins, including signal-triggered drain.
    def is_ready() -> Bool
    # Drains completed events without running logging callbacks. Event capacity includes in-flight reservations.
    def take_events() -> List[HttpEvent]
    # Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.
    def address() -> String
    # Stops accepting connections, waits up to the grace period for in-flight requests, then cancels the rest and waits for them.
    # SIGINT/SIGTERM drains the same way when grace is nonzero: in-flight requests finish within the grace period before the program exits 130/143.
    # Safe to call repeatedly. A request handler calling close on its own server faults, and a shutdown error is raised as a fault.
    def close() -> Unit
    # Blocks until the server stops. Returns Ok after a normal `close`, or IoError.Failed with the host's text if serving ended with an error.
    # Cancelling the waiting task stops the wait.
    def wait() -> Result[Unit, IoError]

# Per-member counters. Each recognized request is active or has exactly one terminal outcome.
export type HttpStats:
    # Parsed request heads, including application-level rejections; malformed protocol input before a complete head is excluded.
    requests: Int = 0
    # Requests admitted after transport validation.
    admitted: Int = 0
    # Recognized requests rejected before dispatch; orthogonal to their terminal outcome.
    rejected: Int = 0
    # Requests whose response output and handler cleanup completed.
    completed: Int = 0
    # Requests ended by disconnect, reset, cancellation, or failed transport.
    aborted: Int = 0
    # Requests whose configured deadline expired.
    timed_out: Int = 0
    # Requests whose callback faulted; takes precedence over timeout and abort.
    faulted: Int = 0
    # Recognized requests still retaining transport or callback ownership.
    active_requests: Int = 0
    # Currently open transport connections, including idle sockets and upgrades.
    active_connections: Int = 0
    # Decoded HTTP body bytes observed by transport, including automatic drain; excludes WebSocket frames.
    request_body_bytes: Int = 0
    # HTTP payload bytes submitted for output after body suppression; may include bytes not delivered to the peer.
    response_body_bytes: Int = 0
    # Terminal requests whose event could not reserve capacity; zero when delivery is disabled.
    dropped_events: Int = 0
    # Accepted TCP sockets, including sockets immediately rejected by the connection cap.
    connections: Int = 0
    # Accepted sockets closed before setup because the connection cap or drain rejected them.
    rejected_connections: Int = 0
    # Listener accept failures other than interruption and WouldBlock.
    accept_errors: Int = 0
    # Malformed HTTP/1 heads and HTTP/2 connection-level protocol failures.
    protocol_errors: Int = 0
    # TLS negotiation failures; deadline expiry is counted by connection_timeouts instead.
    tls_failures: Int = 0
    # Expired connection deadlines without a recognized request, including idle/TLS/header waits.
    connection_timeouts: Int = 0

# Bounded access event. No headers, query strings, credentials, or body contents are included.
export type HttpEvent:
    # Method, capped at 32 UTF-8 bytes.
    method: String
    # Path without query, capped at 2048 UTF-8 bytes.
    path: String
    # Matched route pattern, capped at 2048 bytes; empty when unset.
    route: String
    # Direct transport peer, capped at 128 bytes.
    peer_address: String
    # Transport scheme: http or https.
    scheme: String
    # Final response status, or zero if no response was selected.
    status: Int
    # Elapsed time through output ownership and callback cleanup.
    elapsed: Duration
    # Decoded HTTP body bytes observed by transport, including automatic drain; excludes WebSocket frames.
    request_body_bytes: Int
    # HTTP payload bytes submitted for output after body suppression; may include bytes not delivered to the peer.
    response_body_bytes: Int
    # One terminal outcome: completed, aborted, timed_out, or faulted.
    outcome: String
    # Whether transport validation or admission rejected this request before dispatch.
    rejected: Bool

# Request and response limits, deadlines, graceful shutdown, and TLS server settings.
export type HttpServerOptions:
    # Capacity shared by queued and in-flight event reservations. Positive enables events; none disables delivery while counters remain available.
    event_capacity: Optional[Int] = none
    # Most admitted exchanges, from validated headers through output and cleanup; excess requests receive 503. Must be positive; none sets no cap.
    max_requests: Optional[Int] = none
    # Most open sockets, including TLS handshakes, idle keep-alive, and upgrades. Excess sockets close immediately. Must be positive; none sets no cap.
    max_connections: Optional[Int] = none
    # Largest accepted request body, in bytes. Must be nonnegative; none sets no cap.
    max_body_bytes: Optional[Int] = none
    # Most response body bytes a handler may write, in bytes. Must be nonnegative; none sets no cap.
    max_response_bytes: Optional[Int] = none
    # Largest accepted request header block and largest response header block, in bytes. Must be positive; none sets no cap.
    max_header_bytes: Optional[Int] = none
    # Absolute exchange budget from the first request byte through body, callback, and output. none sets no deadline.
    timeout: Optional[Duration] = none
    # Absolute budget for assembling request headers; none sets no deadline.
    header_timeout: Optional[Duration] = none
    # Budget for TLS handshakes and idle keep-alive sockets; none waits indefinitely.
    idle_timeout: Optional[Duration] = none
    # Maximum time without write progress while output is pending; none waits indefinitely.
    write_timeout: Optional[Duration] = none
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

# Incoming request metadata and a lazy, single-consumer body stream.
# Middleware can reject a request without reading its body; read_body buffers only on demand.
# A request and its body belong to the current handler scope.
# Example: `request.params.get("id")` reads a captured route parameter.
export type Request:
    # Internal route observation shared through middleware copies.
    matched_route: Shared[String] = share("")
    # Request method; defaults to GET for synthetic requests.
    method: HttpMethod = HttpMethod.Get
    # Decoded normalized path; defaults to / for synthetic requests.
    path: String = "/"
    # Raw query without the leading question mark.
    query: String = ""
    # Routing path before the first explicit rewrite; none until rewritten.
    original_path: Optional[String] = none
    # Raw query before the first explicit rewrite; none until rewritten.
    original_query: Optional[String] = none
    # Internal rewrite count; each request permits at most eight explicit rewrites.
    rewrite_count: Int = 0
    # Received fields with repeated values preserved.
    headers: HttpHeaders = headers()
    # Lazy single-consumer stream; reading can suspend and returns transport errors.
    body: ReadStream = from_bytes("".to_bytes())
    # Named route captures, filled before route middleware and the handler.
    params: Map[String, String] = Map[String, String]()
    # Protocol name reported by the transport, or empty for synthetic requests.
    protocol: String = ""
    # Direct transport peer as host:port; empty for synthetic requests.
    peer_address: String = ""
    # Transport scheme, http or https; forwarded headers do not override it.
    scheme: String = ""

impl Request:
    # Copies this request with a normalized decoded routing path. Query is preserved unless supplied.
    # Original routing inputs remain available; more than eight rewrites or invalid paths fail.
    def rewrite(
        path: String,
        query: Optional[String] = none
    ) -> Result[Request, HttpError]:
        if (
            self.rewrite_count < 0
            or self.rewrite_count >= 8
            or path.byte_length() > 8192
            or not path.starts_with("/")
            or path.contains("?")
            or path.contains("#")
            or path.contains("\\")
        ): return error(HttpError.InvalidInput)

        for code in path.scalar_values():
            if code < 32 or code == 127: return error(HttpError.InvalidInput)
        for part in path.split("/"):
            if part == "." or part == "..": return error(HttpError.InvalidInput)
        if path != "/" and (path.ends_with("/") or path.contains("//")): return error(
            HttpError.InvalidInput
        )

        if let value = query:
            if value.byte_length() > 8192 or value.contains("#"): return error(
                HttpError.InvalidInput
            )

            for code in value.scalar_values():
                if code < 32 or code == 127: return error(HttpError.InvalidInput)

        var updated = self.clone()

        if updated.original_path.is_none():
            updated.original_path = some(self.path.clone())
            updated.original_query = some(self.query.clone())

        updated.path = path.clone()
        if let value = query: updated.query = value.clone()
        updated.params = Map[String, String]()
        updated.rewrite_count += 1
        return ok(updated)

    # Parses the query while preserving duplicate entries; malformed input is InvalidInput.
    def query_entries(
        max_entries: Optional[Int] = none
    ) -> Result[List[QueryEntry], HttpError]:
        let result = parse_query(self.query, max_entries)
        if let entries = result:
            return ok(entries)

        return error(HttpError.InvalidInput)

    # Reads the remaining body, optionally capped in bytes. Exceeding the cap is an I/O error.
    def read_body(max_bytes: Optional[Int] = none) -> Result[Bytes, IoError]:
        return read_all(self.body, max_bytes)

# Client metadata resolved using an explicitly trusted proxy chain.
export type ClientInfo:
    # First untrusted numeric address walking right-to-left, or the leftmost address when every hop is trusted.
    address: IpAddress
    # Direct transport scheme, or the trusted proxy's reported scheme. This does not prove end-to-end TLS.
    scheme: String
    # Whether an explicitly trusted direct proxy supplied the metadata.
    forwarded: Bool = False

def trusted_proxy(address: IpAddress, trusted: List[Cidr]) -> Bool:
    for cidr in trusted:
        if contains_ip(cidr, address).get(): return True
    return False

def peer_ip(peer: String) -> Result[IpAddress, HttpError]:
    var host = ""
    var port = ""

    if peer.starts_with("["):
        let parts = peer.split("]:")
        if parts.length() != 2: return error(HttpError.InvalidInput)

        host = parts[0].slice(1, parts[0].byte_length()).get()
        port = parts[1].clone()
    else:
        let parts = peer.split(":")
        if parts.length() != 2: return error(HttpError.InvalidInput)

        host = parts[0].clone()
        port = parts[1].clone()

    if port == "" or port.byte_length() > 5: return error(HttpError.InvalidInput)

    for digit in port.scalar_values():
        if digit < 48 or digit > 57: return error(HttpError.InvalidInput)

    let parsed = parse_ip(host)
    if parsed.is_error(): return error(HttpError.InvalidInput)

    return ok(parsed.get())

# Resolves X-Forwarded-For only after the direct peer matches trusted_proxies.
# Repeated fields retain wire order. Numeric IPs only: no ports, zones, names, or obfuscated identifiers.
# X-Forwarded-Proto must be one http/https value; the trusted proxy MUST overwrite client-supplied values.
# RFC Forwarded is intentionally ignored. Untrusted forwarding headers are ignored entirely.
# IPv4-mapped IPv6 is normalized by parse_ip before CIDR matching. Limits must be positive.
export def client_info(
    request: Request,
    trusted_proxies: List[Cidr] = [],
    max_forwarded_bytes: Int = 8192,
    max_forwarded_hops: Int = 32
) -> Result[ClientInfo, HttpError]:
    if max_forwarded_bytes <= 0 or max_forwarded_hops <= 0: return error(
        HttpError.InvalidInput
    )

    let peer = try peer_ip(request.peer_address)
    if not trusted_proxy(peer, trusted_proxies): return ok(
        ClientInfo(peer, request.scheme.clone())
    )

    var total = 0

    for name in ["X-Forwarded-For", "X-Forwarded-Proto"]:
        if let values = request.headers.values(name):
            for value in values:
                if value.length() > max_forwarded_bytes - total: return error(
                    HttpError.LimitExceeded
                )

                total += value.length()

    var addresses = List[IpAddress]()

    if let values = request.headers.values("X-Forwarded-For"):
        for value in values:
            let decoded = value.decode_utf8()
            if decoded.is_none(): return error(HttpError.InvalidInput)

            for token in decoded.get().split(","):
                if addresses.length() >= max_forwarded_hops: return error(
                    HttpError.LimitExceeded
                )

                let address = parse_ip(token.trim())
                if address.is_error(): return error(HttpError.InvalidInput)

                addresses.append(address.get())

    var scheme = request.scheme.clone()
    var forwarded = addresses.length() > 0

    if let values = request.headers.values("X-Forwarded-Proto"):
        if values.length() != 1: return error(HttpError.InvalidInput)

        let decoded = values[0].decode_utf8()
        if decoded.is_none(): return error(HttpError.InvalidInput)

        let value = decoded.get().trim()
        if value != "http" and value != "https": return error(HttpError.InvalidInput)

        scheme = value.clone()
        forwarded = True

    var address = peer
    while addresses.length() > 0 and trusted_proxy(address, trusted_proxies):
        address = addresses.pop().get()
    return ok(ClientInfo(address, scheme, forwarded))

# JSON request decoding failures, separated by the action an API should take.
# Example: UnsupportedMediaType usually maps to 415; MalformedJson maps to 400.
export type RequestDecodeError:
    # Missing, repeated, or unsupported Content-Type, including a non-UTF-8 charset.
    case UnsupportedMediaType
    # The body is not valid UTF-8 JSON syntax.
    case MalformedJson
    # Valid JSON does not match the requested type or required fields.
    case InvalidValue
    # Reading the request failed, including an explicit body byte limit.
    case Read(
        # Underlying body-stream failure, including configured byte limits.
        cause: IoError
    )
    # JSON parsing exceeded a configured limit or received invalid limits.
    case Json(
        # Underlying parser limit or invalid-limit failure.
        cause: JsonError
    )

impl Error for RequestDecodeError:
    # Returns a diagnostic for media, syntax, shape, read, or parser-limit failures.
    def message() -> String:
        match self:
            case UnsupportedMediaType: return "HTTP request: expected application/json with UTF-8 encoding"
            case MalformedJson: return "HTTP request: malformed JSON"
            case InvalidValue: return "HTTP request: JSON does not match the requested type"
            case Read(cause): return cause.message()
            case Json(cause): return cause.message()

# Reads a JSON request once, enforcing optional JSON budgets before typed decoding.
# application/json and application/*+json are accepted; charset, when supplied, must be UTF-8.
# Syntax and type failures remain distinct. Unknown fields are rejected by default.
export def decode_json[T](
    request: Request,
    limits: JsonLimits = JsonLimits(),
    ignore_unknown_fields: Bool = False
) -> Result[T, RequestDecodeError]:
    let content_types = request.headers.text("Content-Type")
    if content_types.is_error(): return error(RequestDecodeError.UnsupportedMediaType)
    if content_types.get().is_none(): return error(
        RequestDecodeError.UnsupportedMediaType
    )

    let values = content_types.get().get()
    if values.length() != 1: return error(RequestDecodeError.UnsupportedMediaType)

    let parts = values[0].lower().split(";")
    let media = parts[0].trim()
    if (
        media != "application/json"
        and not (media.starts_with("application/") and media.ends_with("+json"))
    ):
        return error(RequestDecodeError.UnsupportedMediaType)

    for index in range(1, parts.length()):
        let parameter = parts[index].trim()
        if parameter != "charset=utf-8" and parameter != "charset=\"utf-8\"":
            return error(RequestDecodeError.UnsupportedMediaType)

    let body = request.read_body(limits.max_bytes)
    if body.is_error(): return error(RequestDecodeError.Read(body.err().clone()))

    let text = body.get().decode_utf8()
    if text.is_none(): return error(RequestDecodeError.MalformedJson)

    let syntax = parse[JsonValue](text.get(), limits)

    if syntax.is_error():
        if syntax.err() == JsonError.InvalidData: return error(
            RequestDecodeError.MalformedJson
        )

        return error(RequestDecodeError.Json(syntax.err().clone()))

    let value = parse[T](text.get(), limits, ignore_unknown_fields)

    if value.is_error():
        if value.err() == JsonError.InvalidData: return error(
            RequestDecodeError.InvalidValue
        )

        return error(RequestDecodeError.Json(value.err().clone()))

    match value:
        case ok(decoded): return ok(decoded)
        case error(cause): return error(RequestDecodeError.Json(cause))

# Response work deferred until middleware returns and headers are committed.
# Stream producers run once with a scoped writer; HEAD, 204, 205 and 304 skip producers.
# Example: `Body.Buffered("hello".to_bytes())`.
export type Body:
    # A complete in-memory body, written after middleware returns.
    case Buffered(
        # Raw response bytes written after the headers are committed.
        data: Bytes
    )
    # A deferred producer; transport backpressure can suspend its writes.
    case Stream(
        # Called once with a writer that expires when this callback returns.
        produce: Callable[[WriteStream], Result[Unit, IoError]]
    )
    # A deferred WebSocket handshake followed by a scoped session callback.
    case Upgrade(
        # Runs after a successful handshake; returning closes the socket.
        handler: Callable[[WebSocket], Result[Unit, WebSocketError]],
        # Allowed browser origins; empty requires the request origin to match its host.
        allowed_origins: List[String],
        # Acceptable subprotocols in preference order.
        subprotocols: List[String],
        # Maximum message size in bytes, or none for no explicit cap.
        max_message_bytes: Optional[Int]
    )

# A response whose headers remain mutable while middleware unwinds.
# Example: `text_response("hello")` creates a UTF-8 text response.
export type Response:
    # Final HTTP status, normally 200 through 599; WebSocket responses use 101.
    status: Int
    # Mutable response fields; host-owned framing fields cannot be supplied.
    headers: HttpHeaders
    # Buffered bytes, a deferred producer, or a deferred WebSocket session.
    body: Body
    # Optional known representation length for streaming or HEAD/304 metadata; buffered ordinary responses infer their byte length.
    content_length: Optional[Int] = none

# Creates a buffered UTF-8 plain-text response.
export def text_response(text: String, status: Int = 200) -> Response:
    let fields = headers()
    fields.append("Content-Type", "text/plain; charset=utf-8".to_bytes()).get()
    return Response(status, fields, Body.Buffered(text.to_bytes()))

# Serializes a value as JSON, preserving serialization errors.
export def json_response[T](value: T, status: Int = 200) -> Result[Response, JsonError]:
    let text = try stringify(value)
    let fields = headers()
    fields.append("Content-Type", "application/json".to_bytes()).get()
    return ok(Response(status, fields, Body.Buffered(text.to_bytes())))

# Defers a body producer until headers are sent. Writes honor transport backpressure.
# The writer is invalid after the producer returns; retain no reference to it.
export def stream_response(
    produce: Callable[[WriteStream], Result[Unit, IoError]],
    content_type: String = "application/octet-stream",
    status: Int = 200
) -> Response:
    let fields = headers()
    fields.append("Content-Type", content_type.to_bytes()).get()
    return Response(status, fields, Body.Stream(produce))

# Creates an empty redirect response. The location must be a valid header value.
export def redirect_response(location: String, status: Int = 303) -> Response:
    let fields = headers()
    fields.append("Location", location.to_bytes()).get()
    return Response(status, fields, Body.Buffered("".to_bytes()))

# Defers the HTTP/1.1 WebSocket handshake until middleware has returned.
# Middleware may add cookies and other non-protocol headers. The callback owns the
# socket only until it returns; the server closes it on return, error, or cancellation.
export def websocket_response(
    handler: Callable[[WebSocket], Result[Unit, WebSocketError]],
    allowed_origins: List[String] = [],
    subprotocols: List[String] = [],
    max_message_bytes: Optional[Int] = none
) -> Response:
    return Response(
        101, headers(),
        Body.Upgrade(handler, allowed_origins, subprotocols, max_message_bytes)
    )

# Internal callable wrapper stored by Router.use.
# Example: `Middleware(lambda request, next: next(request))`.
export type Middleware:
    # Wraps the downstream continuation, which may run at most once before this call returns.
    call: Callable[[Request, Callable[[Request], Response]], Response]

# A route registration; use Router.route to validate paths and detect duplicates.
# Example: `Route("GET", "/", lambda request: text_response("home"))`.
export type Route:
    # Case-sensitive HTTP method token.
    method: String
    # Validated route pattern containing literal, :parameter, or terminal *wildcard segments.
    path: String
    # Invoked with the matched request and its parameters.
    handler: Callable[[Request], Response]
    # Snapshot of the mounted middleware wrapping this registration.
    middleware: List[Middleware] = []

# Internal middleware snapshot for a mounted prefix, including unmatched requests.
# Example: `MountedMiddleware("/api", [])`.
export type MountedMiddleware:
    # Literal mount prefix with no trailing slash except /.
    prefix: String
    # Middleware wrapping this prefix, ordered from outer to inner.
    chain: List[Middleware]

# Routes and scoped middleware. Literal segments outrank :parameters, then terminal
# *wildcards. Paths are case-sensitive; trailing slashes are significant.
# use applies to every route in this router, regardless of registration order.
# mount snapshots its child; later changes to that child do not affect this router.
#
# ```manuscript
# var api = Router()
# api.get("/users/:id", lambda request: text_response(request.params.get("id").get()))
# var routes = Router()
# routes.mount("/api", api)
# ```
export type Router:
    # Internal registrations; add entries through the route methods.
    routes: List[Route] = []
    # Internal outer middleware; append through use.
    middleware: List[Middleware] = []
    # Internal flattened mount snapshots; add children through mount.
    mounts: List[MountedMiddleware] = []

def segments(path: String) -> List[String]:
    if path == "/": return []

    return path.drop(1).split("/")

def validate_path(path: String) -> Unit:
    if not path.starts_with("/") or path.contains("?") or path.contains("#"):
        panic("Router: path must start with / and contain no query or fragment")

    var names = Set[String]()
    let parts = segments(path)

    for index in 0..parts.length():
        let part = parts[index]
        if part == "." or part == ".." or (part == "" and index + 1 < parts.length()):
            panic("Router: path must be normalized")

        if part.starts_with(":") or part.starts_with("*"):
            let name = part.drop(1)
            if name == "" or names.contains(name):
                panic("Router: parameter names must be nonempty and unique")
            names.add(name)

        if part.starts_with("*") and index + 1 != parts.length():
            panic("Router: a wildcard must be the last segment")

def shape(path: String) -> String:
    return (
        segments(path)
        .map(
            lambda part:
                if part.starts_with(":"): return ":"
                if part.starts_with("*"): return "*"

                return part.clone()
        )
        .join("/")
    )

def rank(part: String) -> Int:
    if part.starts_with("*"): return 0
    if part.starts_with(":"): return 1

    return 2

def more_specific(left: String, right: String) -> Bool:
    let a = segments(left)
    let b = segments(right)

    for index in 0..a.length():
        if index >= b.length(): return False

        let x = rank(a[index])
        let y = rank(b[index])
        if x != y: return x > y

    return a.length() < b.length()

def parameters(pattern: String, path: String) -> Optional[Map[String, String]]:
    let expected = segments(pattern)
    let actual = segments(path)
    var result = Map[String, String]()

    for index in 0..expected.length():
        let part = expected[index]

        if part.starts_with("*"):
            if index > actual.length(): return none

            var rest = List[String]()
            for at in index..actual.length():
                rest.append(actual[at].clone())
            result.add(part.drop(1), rest.join("/"))
            return some(result)

        if index >= actual.length(): return none

        if part.starts_with(":"):
            if actual[index] == "": return none

            result.add(part.drop(1), actual[index].clone())
        elif part != actual[index]:
            return none

    if expected.length() != actual.length(): return none

    return some(result)

type NextState:
    active: Bool = True
    called: Bool = False

# Cleanup-owned state across callbacks; close is deliberately empty.
type Owned[T]:
    value: T

impl Closeable for Owned[T]:
    var def close() -> Unit: ()

type NextScope:
    state: Shared[NextState]
    next: Callable[[Request], Response]

impl Closeable for NextScope:
    var def close() -> Unit:
        with var state_guard = lock(self.state):
            state_guard.value.active = False

def copy_callable[T: Clonable](value: T) -> T:
    return value.clone()

def next_scope(
    chain: List[Middleware],
    index: Int,
    handler: Callable[[Request], Response]
) -> NextScope:
    msrt_shield_enter()

    with let shield = ControlShield():
        let saved_chain = chain.clone()
        let saved_handler = copy_callable(handler)
        let used = share(NextState())

        let next = lambda (incoming: Request) -> Response:
            if not used.get().active: panic("middleware: next is no longer active")
            if used.get().called: panic("middleware: next may be called only once")
            with var state_guard = lock(used):
                state_guard.value.called = True
            return invoke(saved_chain, index + 1, saved_handler, incoming)

        return NextScope(used, next)

def invoke(
    chain: List[Middleware],
    index: Int,
    handler: Callable[[Request], Response],
    request: Request
) -> Response:
    if index >= chain.length(): return handler(request)

    with let scope = next_scope(chain, index, handler):
        return chain[index].call(request, scope.next)

def outer_handler(router: Router) -> Callable[[Request], Response]:
    msrt_shield_enter()

    with let shield = ControlShield():
        let saved = router.clone()
        return lambda incoming: saved.dispatch(incoming)

type RoutePlan:
    chain: List[Middleware]
    handler: Callable[[Request], Response]
    request: Request

impl Router:
    # Adds outer middleware. next may be called at most once, only during this call.
    var def use(
        middleware: Callable[[Request, Callable[[Request], Response]], Response]
    ) -> Unit:
        self.middleware.append(Middleware(middleware))

    # Registers a method and pattern; malformed or duplicate patterns fault.
    var def route(
        method: HttpMethod,
        path: String,
        handler: Callable[[Request], Response]
    ) -> Unit:
        validate_path(path)

        let token = method.text()
        for route in self.routes:
            if route.method == token and shape(route.path) == shape(path):
                panic("Router: duplicate or ambiguous route")
        self.routes.append(Route(token, path, handler))

    # Registers a GET route.
    var def get(path: String, handler: Callable[[Request], Response]) -> Unit:
        self.route(HttpMethod.Get, path, handler)

    # Registers a POST route.
    var def post(path: String, handler: Callable[[Request], Response]) -> Unit:
        self.route(HttpMethod.Post, path, handler)

    # Registers a PUT route.
    var def put(path: String, handler: Callable[[Request], Response]) -> Unit:
        self.route(HttpMethod.Put, path, handler)

    # Registers a PATCH route.
    var def patch(path: String, handler: Callable[[Request], Response]) -> Unit:
        self.route(HttpMethod.Patch, path, handler)

    # Registers a DELETE route.
    var def delete(path: String, handler: Callable[[Request], Response]) -> Unit:
        self.route(HttpMethod.Delete, path, handler)

    # Registers a HEAD route.
    var def head(path: String, handler: Callable[[Request], Response]) -> Unit:
        self.route(HttpMethod.Head, path, handler)

    # Registers a OPTIONS route.
    var def options(path: String, handler: Callable[[Request], Response]) -> Unit:
        self.route(HttpMethod.Options, path, handler)

    # Snapshots a child under a literal prefix; its middleware also wraps its 404/405 responses.
    var def mount(prefix: String, router: Router) -> Unit:
        validate_path(prefix)
        if prefix != "/" and prefix.ends_with("/"):
            panic("Router: mount prefix must not end with /")
        if prefix.contains(":") or prefix.contains("*"):
            panic("Router: mount prefixes must contain literal segments")

        var additions = [MountedMiddleware(prefix.clone(), router.middleware.clone())]

        for mount in router.mounts:
            let chain = router.middleware.concat(mount.chain)

            if mount.prefix == "/":
                additions[0].chain = chain
            else:
                let nested = mount.prefix.clone() if prefix == "/" else prefix + mount.prefix

                additions.append(MountedMiddleware(nested, chain))

        var prefixes = List[String]()
        for mount in self.mounts: prefixes.append(mount.prefix.clone())

        for mount in additions:
            if prefixes.contains(mount.prefix): panic("Router: duplicate mount prefix")
            prefixes.append(mount.prefix.clone())

        for route in router.routes:
            let path = route.path.clone() if prefix == "/" else prefix + route.path

            for existing in self.routes:
                if (
                    existing.method == route.method
                    and shape(existing.path) == shape(path)
                ):
                    panic("Router: duplicate or ambiguous route")

        for mount in additions: self.mounts.append(mount.clone())

        for route in router.routes:
            let path = route.path.clone() if prefix == "/" else prefix + route.path

            self.route(HttpMethod.Custom(route.method.clone()), path, route.handler)

            var chain = router.middleware.clone()
            for middleware in route.middleware:
                chain.append(middleware.clone())
            self.routes[self.routes.length() - 1].middleware = chain

    # Dispatches through middleware without a network connection; useful for application tests.
    def handle(request: Request) -> Response:
        with let handler = Owned(outer_handler(self)):
            return invoke(self.middleware, 0, handler.value, request)

    # Internal route selection; callers should use handle to include outer middleware.
    def dispatch(request: Request) -> Response:
        with let plan = Owned(route_plan(self, request)):
            return invoke(plan.value.chain, 0, plan.value.handler, plan.value.request)

def route_plan(router: Router, request: Request) -> RoutePlan:
    msrt_shield_enter()

    with let shield = ControlShield():
        var best = ""
        for route in router.routes:
            if parameters(route.path, request.path).is_some():
                if best == "" or more_specific(route.path, best):
                    best = route.path.clone()
        if best == "":
            return RoutePlan(
                mount_chain(router, request.path),
                lambda incoming: text_response("Not found", 404), request.clone()
            )

        let method = request.method.text()
        var allowed = List[String]()
        var selected: Optional[Route] = none
        var fallback: Optional[Route] = none

        for route in router.routes:
            if shape(route.path) != shape(best): continue

            if not allowed.contains(route.method): allowed.append(route.method.clone())
            if route.method == method: selected = some(route.clone())
            if method == "HEAD" and route.method == "GET": fallback = some(
                route.clone()
            )

        if allowed.contains("GET") and not allowed.contains("HEAD"): allowed.append(
            "HEAD"
        )
        if not allowed.contains("OPTIONS"): allowed.append("OPTIONS")
        if selected.is_none(): selected = fallback

        if let route = selected:
            with var flag_guard = lock(request.matched_route):
                flag_guard.value = route.path.clone()

            var incoming = request.clone()
            incoming.params = parameters(route.path, incoming.path).get()
            return RoutePlan(
                route.middleware.clone(), copy_callable(route.handler), incoming
            )

        let response = text_response(
            "" if method == "OPTIONS" else "Method not allowed",
            204 if method == "OPTIONS" else 405
        )
        response.headers.append("Allow", allowed.join(", ").to_bytes()).get()
        return RoutePlan(
            mount_chain(router, request.path), lambda incoming: response.clone(),
            request.clone()
        )

def mount_chain(router: Router, path: String) -> List[Middleware]:
    var chain = List[Middleware]()
    var length = -1

    for mount in router.mounts:
        let matches = (
            mount.prefix == "/"
            or path == mount.prefix
            or path.starts_with(mount.prefix + "/")
        )

        if matches and mount.prefix.length() > length:
            chain = mount.chain.clone()
            length = mount.prefix.length()

    return chain

type ExchangeReader:
    exchange: Shared[HttpExchange]

impl ReadStream for ExchangeReader:
    var def close() -> Unit: self.exchange.get().close()

    var def read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]:
        return self.exchange.get().read(max_bytes)

type WriterScope:
    active: Shared[Bool]
    writer: WriteStream

impl Closeable for WriterScope:
    var def close() -> Unit:
        with var flag_guard = lock(self.active):
            flag_guard.value = False

type ExchangeWriter:
    exchange: Shared[HttpExchange]
    active: Shared[Bool]

impl WriteStream for ExchangeWriter:
    var def close() -> Unit:
        if not self.active.get(): return

        with var flag_guard = lock(self.active):
            flag_guard.value = False
        self.exchange.get().close()

    var def flush() -> Result[Unit, IoError]:
        if not self.active.get(): return error(IoError.Closed)

        return ok(())

    var def write(data: String) -> Result[Unit, IoError]:
        if not self.active.get(): return error(IoError.Closed)

        return self.exchange.get().write(data)

    var def write_bytes(data: Bytes) -> Result[Unit, IoError]:
        if not self.active.get(): return error(IoError.Closed)

        return self.exchange.get().write_bytes(data)

def writer_scope(exchange: Shared[HttpExchange]) -> WriterScope:
    msrt_shield_enter()

    with let shield = ControlShield():
        let active = share(True)
        return WriterScope(active, ExchangeWriter(exchange, active))

def produce_body(
    exchange: Shared[HttpExchange],
    produce: Callable[[WriteStream], Result[Unit, IoError]]
) -> Result[Unit, IoError]:
    with let scope = writer_scope(exchange):
        return produce(scope.writer)

def body_action(body: Body) -> Callable[[Shared[HttpExchange]], Result[Unit, IoError]]:
    msrt_shield_enter()

    with let shield = ControlShield():
        match body:
            case Buffered(data):
                let owned = data.clone()
                return lambda exchange: exchange.get().write_bytes(owned)
            case Stream(produce):
                let owned = copy_callable(produce)
                return lambda exchange: produce_body(exchange, owned)
            case Upgrade(handler, origins, protocols, limit): return lambda exchange: error(
                IoError.InvalidInput
            )

def send_body(exchange: Shared[HttpExchange], body: Body) -> Result[Unit, HttpError]:
    with let action = Owned(body_action(body)):
        let result = action.value(exchange)
        if result.is_error(): return error(HttpError.Failed(result.err().message()))

        return ok(())

type UpgradePlan:
    handler: Callable[[WebSocket], Result[Unit, WebSocketError]]
    origins: List[String]
    protocols: List[String]
    limit: Optional[Int]

def upgrade_plan(body: Body) -> Optional[UpgradePlan]:
    msrt_shield_enter()

    with let shield = ControlShield():
        match body:
            case Upgrade(handler, origins, protocols, limit): return some(
                UpgradePlan(
                    copy_callable(handler), origins.clone(), protocols.clone(), limit
                )
            )
            case _: return none

def run_websocket(
    exchange: HttpExchange,
    handler: Callable[[WebSocket], Result[Unit, WebSocketError]],
    origins: List[String],
    protocols: List[String],
    limit: Optional[Int],
    fields: HttpHeaders
) -> Result[Unit, WebSocketError]:
    with let socket = try exchange.upgrade_with_headers(
        origins, protocols, fields, limit
    ):
        return handler(socket)

def send_upgrade(
    exchange: HttpExchange,
    plan: UpgradePlan,
    fields: HttpHeaders
) -> Result[Unit, WebSocketError]:
    return run_websocket(
        exchange, plan.handler, plan.origins, plan.protocols, plan.limit, fields
    )

def send(exchange: Shared[HttpExchange], response: Response) -> Result[Unit, HttpError]:
    with let upgrade = Owned(upgrade_plan(response.body)):
        if upgrade.value.is_some():
            if response.status != 101: return error(HttpError.InvalidInput)

            let result = send_upgrade(
                exchange.get(), upgrade.value.get(), response.headers
            )
            if result.is_error(): return error(HttpError.Failed(result.err().message()))

            return ok(())

    var length = response.content_length.clone()

    if (
        length.is_none()
        and response.status != 204
        and response.status != 205
        and response.status != 304
    ):
        match response.body:
            case Buffered(data): length = some(data.length())
            case _: ()

    try exchange.get().send_headers(response.status, response.headers, length)
    if (
        exchange.get().method().text() == "HEAD"
        or response.status == 204
        or response.status == 205
        or response.status == 304
    ):
        return ok(())

    return send_body(exchange, response.body)

type DispatchScope:
    exchange: Shared[HttpExchange]
    request: Request

impl Closeable for DispatchScope:
    var def close() -> Unit:
        self.exchange.get().set_route(self.request.matched_route.get().clone())

def dispatch_scope(exchange: HttpExchange) -> DispatchScope:
    msrt_shield_enter()

    with let shield = ControlShield():
        let shared = share(exchange)
        return DispatchScope(
            shared,
            Request(
                method: shared.get().method(), path: shared.get().path(),
                query: shared.get().query(), headers: shared.get().headers(),
                body: ExchangeReader(shared), protocol: shared.get().protocol(),
                peer_address: shared.get().peer_address(), scheme: shared.get().scheme()
            )
        )

def dispatch_exchange(
    router: Shared[Router],
    exchange: HttpExchange
) -> Result[Unit, HttpError]:
    with let scope = dispatch_scope(exchange):
        with let response = Owned(router.get().handle(scope.request)):
            return send(scope.exchange, response.value)

# Internal shared lifecycle state for a Server and its copies.
# Example: `ServerState()` is an unstarted server.
export type ServerState:
    # Whether run has been attempted; prevents a second start.
    started: Bool = False
    # Whether a native server was bound and published successfully.
    ready: Bool = False
    # Whether close has been requested, including during startup.
    stopped: Bool = False
    # Shared native server after binding, or none before publication.
    running: Optional[Shared[HttpServer]] = none
    # Group readiness barrier has been released.
    released: Bool = False
    # One-shot token of run while it waits for the group barrier, or zero.
    start_waiter: Int = 0
    # A grouped close request has already been sent to the supervisor.
    stop_requested: Bool = False

type RunningScope:
    running: Shared[HttpServer]

impl Closeable for RunningScope:
    var def close() -> Unit: self.running.get().close()

# Scoped application server. run binds once and blocks until shutdown; another task
# can call close on a copy of this handle. Every copy refers to the same lifecycle.
# Example: `Server("127.0.0.1:8080").run(routes)`.
export type Server:
    # TCP address to bind; port 0 asks the operating system to select a port.
    listen_address: String
    # Transport limits, TLS, and shutdown grace used when run starts.
    options: HttpServerOptions = HttpServerOptions()
    # Internal lifecycle state shared by every copy of the handle.
    state: Shared[ServerState] = share(ServerState())
    # Internal member bootstrap; none for a local application.
    member: Optional[Shared[NativeHttpMember]] = none
    # Zero-based identity of this member; zero in local execution.
    member_index: Int = 0
    # Total number of members; one in local execution.
    member_count: Int = 1

impl Server:
    # True while this member is activated and accepting, false before startup and during drain.
    def is_ready() -> Bool:
        if self.state.get().stopped or self.state.get().stop_requested: return False
        if let running = self.state.get().running: return running.get().is_ready()

        return False

    # Returns counters for this member, or zero counters before run starts.
    def stats() -> HttpStats:
        if let running = self.state.get().running: return running.get().stats()

        return HttpStats()

    # Drains this member's completed access events; empty before run starts.
    def take_events() -> List[HttpEvent]:
        if let running = self.state.get().running: return running.get().take_events()

        return List[HttpEvent]()

    # Returns the actual bound address once run has started, including an OS-selected port.
    def address() -> Optional[String]:
        if let running = self.state.get().running:
            return some(running.get().address())

        return none

    # Stops accepting and drains according to options.grace. Calling from a handler faults.
    def close() -> Unit:
        if let member = self.member:
            if self.state.get().stopped or self.state.get().stop_requested: return ()

            if let active = self.state.get().running: msrt_http_server_check_close(
                active.get()
            )
            with var state_guard = lock(self.state):
                state_guard.value.stop_requested = True

            let _requested = msrt_http_member_write(member.get(), "STOP".to_bytes())
            return ()

        self.close_local()

    # Internal shutdown from the group controller; it never requests another group stop.
    def close_local() -> Unit:
        with var state_guard = lock(self.state):
            state_guard.value.stopped = True

        let running = self.state.get().running
        let waiting = self.state.get().start_waiter
        if waiting != 0: msrt_channel_post(waiting)
        if let active = running: active.get().close()

    # Freezes routes, binds, and waits for shutdown. Calling again returns InvalidInput or Closed.
    def run(routes: Router) -> Result[Unit, HttpError]:
        if self.state.get().stopped: return error(HttpError.Closed)
        if self.state.get().started: return error(HttpError.InvalidInput)

        with var starting_guard = lock(self.state):
            starting_guard.value.started = True

        let frozen = share(routes)
        let handler: Callable[[HttpExchange], Result[Unit, HttpError]] = lambda exchange: dispatch_exchange(
            frozen, exchange
        )

        let acquired = match self.member:
            case some(member): msrt_net_member_serve_stream(
                member.get(), network(), handler, self.options
            )
            case none: network().serve_stream(
                self.listen_address, handler, self.options
            )

        let running = share(try acquired)

        with let scope = RunningScope(running):
            if self.state.get().stopped: return error(HttpError.Closed)

            with var state_guard = lock(self.state):
                state_guard.value.running = some(running)
                state_guard.value.ready = True

            if let member = self.member:
                try msrt_http_member_write(member.get(), "READY".to_bytes())

                if not self.state.get().released and not self.state.get().stopped:
                    let token = msrt_channel_token()
                    with var waiting_guard = lock(self.state):
                        waiting_guard.value.start_waiter = token
                    msrt_channel_park(token)

                if self.state.get().stopped: return error(HttpError.Closed)

                try msrt_http_server_activate(running.get())

            let result = running.get().wait()
            if result.is_error(): return error(HttpError.Failed(result.err().message()))

        return ok(())

# Runs an application that builds its router and calls server.run exactly once.
# Returning successfully without starting the server is InvalidInput. Startup and
# transport errors propagate; cancellation closes the scoped running server.
#
# ```manuscript
# def application(server: Server) -> Result[Unit, HttpError]:
#     var routes = Router()
#     routes.get("/", lambda request: text_response("hello"))
#     return server.run(routes)
#
# serve("127.0.0.1:8080", application).get()
# ```
#
# Add middleware with routes.use(lambda request, next: next(request)); mount a child
# Router with routes.mount("/api", child). Middleware surrounds routing, including
# automatic 404/405/OPTIONS responses; returned bodies start after middleware unwinds.
# Use stream_response for incremental/SSE output and websocket_response for a scoped
# upgrade callback. A retained writer or middleware continuation expires at scope exit.
#
# Pass execution: workers(4) or execution: processes(4) to run whole handlers on one
# listening address. The application is a capture-free top-level function and runs
# once per member; create databases, configuration and scoped services inside it.
# Limits and cache state are per member. Established connections stay on their member,
# including all HTTP/2 streams; use multiple connections to distribute that workload.
# Workers require cooperative initialization/cleanup. Processes additionally provide
# bounded forced termination; external supervisors can restart a failed group.
#
# Production configurations should set finite request, connection, body/header and
# output limits plus phase/absolute deadlines. Default optional limits are unlimited.
# stats() counts outcomes independently of bounded take_events() delivery. Saturation
# drops new events and increments dropped_events; consumers must not assume lossless logs.
# Scheme/peer metadata is direct transport evidence; client_info requires explicit trusted proxies.
#
# Web helpers compose this router: web supplies cookies, credentials, CORS and forms;
# web_sessions supplies signed expiring cookies; web_multipart streams bounded uploads;
# web_assets supplies conditional/range representations; web_compression supplies gzip;
# web_html supplies escaped HTML; web_cache supplies bounded per-member caching;
# web_build invokes ordinary page handlers for static generation and scoped staging.
# Shared session keys, revocation and distributed cache invalidation are application-owned.
#
# HTTP callback faults become failed responses or connection/stream aborts. Library
# scopes release request resources on cancellation; arbitrary ordinary application
# locals retain the runtime's fault-unwinding limitations. Keep resources in with scopes.
export def serve(
    address: String,
    application: Callable[[Server], Result[Unit, HttpError]],
    options: HttpServerOptions = HttpServerOptions(),
    execution: Execution = Execution.Local
) -> Result[Unit, HttpError]:
    match execution:
        case Local: ()
        case _: return serve_group(address, application, options, execution)

    let server = Server(address, options)
    let result = application(server.clone())
    if result.is_error(): return result
    if not server.state.get().ready: return error(HttpError.InvalidInput)

    return result

# Native launcher owned by the implementation of serve.
# Example: created internally by `serve(..., execution: workers())`.
export extern type NativeHttpGroup

# Native bootstrap owned by one worker/process application scope.
# Example: supplied internally to a grouped Server.
export extern type NativeHttpMember

extern def msrt_http_group_new(
    net: Network,
    address: String,
    runner: Callable[[], Unit],
    config: String,
    processes: Bool,
    count: Optional[Int],
    cleanup_ns: Int
) -> Result[NativeHttpGroup, HttpError]

extern def msrt_http_group_count(group: NativeHttpGroup) -> Int

extern def msrt_http_group_address(group: NativeHttpGroup) -> String

extern def msrt_http_group_spawn(
    group: NativeHttpGroup,
    index: Int
) -> Result[Unit, HttpError]

extern def msrt_http_group_connect(
    group: NativeHttpGroup,
    index: Int
) -> Result[Unit, HttpError]

extern def msrt_http_group_read(
    group: NativeHttpGroup,
    index: Int
) -> Result[Bytes, HttpError]

extern def msrt_http_group_write(
    group: NativeHttpGroup,
    index: Int,
    data: Bytes
) -> Result[Unit, HttpError]

extern def msrt_http_group_post(
    group: NativeHttpGroup,
    index: Int,
    kind: Int
) -> Result[Unit, HttpError]

extern def msrt_http_group_next(group: NativeHttpGroup, timeout_ns: Int) -> Int

extern def msrt_http_group_join(
    group: NativeHttpGroup,
    index: Int,
    timeout_ns: Int
) -> Result[Unit, HttpError]

extern def msrt_http_group_close(group: NativeHttpGroup) -> Unit

extern def msrt_http_group_abort(group: NativeHttpGroup) -> Unit

extern def msrt_shield_enter() -> Unit

extern def msrt_shield_exit() -> Unit

extern def msrt_http_member_take() -> Result[NativeHttpMember, HttpError]

extern def msrt_http_member_connect(member: NativeHttpMember) -> Result[Unit, HttpError]

extern def msrt_http_member_read(member: NativeHttpMember) -> Result[Bytes, HttpError]

extern def msrt_http_member_write(
    member: NativeHttpMember,
    data: Bytes
) -> Result[Unit, HttpError]

extern def msrt_http_member_disarm(member: NativeHttpMember) -> Unit

extern def msrt_http_member_close(member: NativeHttpMember) -> Unit

extern def msrt_net_member_serve_stream(
    member: NativeHttpMember,
    net: Network,
    handler: Callable[[HttpExchange], Result[Unit, HttpError]],
    options: HttpServerOptions
) -> Result[HttpServer, HttpError]

extern def msrt_http_server_activate(server: HttpServer) -> Result[Unit, HttpError]

extern def msrt_http_server_check_close(server: HttpServer) -> Unit

extern def msrt_channel_token() -> Int

extern def msrt_channel_park(token: Int) -> Unit

extern def msrt_channel_post(token: Int) -> Unit

# Where complete application handlers execute. State is initialized separately in each member.
# Example: `workers(4)` serves one address using four independent heaps.
export type Execution:
    # Runs the application on the calling isolate and permits captured application closures.
    case Local
    # Runs named application entries on independent worker threads. Cleanup is cooperative.
    case Workers(
        # Number of members, or none to use available parallelism; must be positive.
        count: Optional[Int],
        # Absolute readiness budget; none waits indefinitely. Cleanup may exceed this budget.
        startup_timeout: Optional[Duration]
    )
    # Runs named application entries in separate processes with enforceable termination.
    case Processes(
        # Number of members, or none to use available parallelism; must be positive.
        count: Optional[Int],
        # Absolute readiness budget; none waits indefinitely.
        startup_timeout: Optional[Duration],
        # Finite final cleanup and parent-loss budget; must be nonnegative.
        cleanup_timeout: Duration
    )

# Selects worker isolates; omitted count uses available parallelism. Initialization and cleanup must cooperate with cancellation.
export def workers(
    count: Optional[Int] = none,
    startup_timeout: Optional[Duration] = 30.seconds
) -> Execution:
    return Execution.Workers(count, startup_timeout)

# Selects child processes; cleanup_timeout also bounds parent-loss cleanup independently of the application scheduler.
export def processes(
    count: Optional[Int] = none,
    startup_timeout: Optional[Duration] = 30.seconds,
    cleanup_timeout: Duration = 30.seconds
) -> Execution:
    return Execution.Processes(count, startup_timeout, cleanup_timeout)

type GroupScope:
    group: Shared[NativeHttpGroup]

impl Closeable for GroupScope:
    var def close() -> Unit: msrt_http_group_close(self.group.get())

# Tracks progress for cancellation cleanup while control readers are still alive.
type GroupProgress:
    ready: Int = 0
    done: Int = 0
    stopping: Bool = False
    draining: Instant

type GroupDrainScope:
    group: Shared[NativeHttpGroup]
    progress: Shared[GroupProgress]
    members: Int
    grace: Optional[Duration]
    cleanup: Duration

impl Closeable for GroupDrainScope:
    var def close() -> Unit:
        with let rollback = GroupAbortScope(self.group, self.progress, self.members):
            # Failed startup rolls back immediately. A running group drains before
            # the enclosing task scope cancels its control readers.
            if self.progress.get().ready != self.members: return
            if self.progress.get().done == self.members: return

            let send_stop = not self.progress.get().stopping

            with var state_guard = lock(self.progress):
                state_guard.value.stopping = True
                if send_stop: state_guard.value.draining = clock().now()

            let started = self.progress.get().draining
            var done = self.progress.get().done + 0

            if send_stop:
                for index in range(0, self.members):
                    let sent = msrt_http_group_write(
                        self.group.get(), index, "STOP".to_bytes()
                    )
                    if sent.is_error(): return

            while done < self.members:
                let remaining = group_drain_remaining(started, self.grace, self.cleanup)
                let event = msrt_http_group_next(self.group.get(), remaining)
                if event < 0: return

                let kind = event % 16
                if kind == 3: return

                if kind == 2: done += 1

            with var finished_guard = lock(self.progress):
                finished_guard.value.done = done

type GroupAbortScope:
    group: Shared[NativeHttpGroup]
    progress: Shared[GroupProgress]
    members: Int

impl Closeable for GroupAbortScope:
    var def close() -> Unit:
        if self.progress.get().done != self.members:
            msrt_http_group_abort(self.group.get())

type ControlShield:
    active: Bool = True

impl Closeable for ControlShield:
    var def close() -> Unit: msrt_shield_exit()

type MemberScope:
    member: Shared[NativeHttpMember]

impl Closeable for MemberScope:
    var def close() -> Unit: msrt_http_member_close(self.member.get())

def group_failure(
    group: Shared[NativeHttpGroup],
    errors: Shared[Map[Int, String]],
    index: Int,
    message: String
) -> Unit:
    with var recorded_guard = lock(errors):
        recorded_guard.value.add(index, message)

    let _posted = msrt_http_group_post(group.get(), index, 3)

def watch_group_member(
    group: Shared[NativeHttpGroup],
    errors: Shared[Map[Int, String]],
    index: Int
) -> Unit:
    msrt_shield_enter()

    with let shield = ControlShield():
        let connected = msrt_http_group_connect(group.get(), index)

        if connected.is_error():
            group_failure(group, errors, index, connected.err().message())
            return

        var ready = False

        while True:
            let read = msrt_http_group_read(group.get(), index)

            if read.is_error():
                group_failure(group, errors, index, read.err().message())
                return

            let message = read.get().decode_utf8().get("")

            if message == "READY" and not ready:
                ready = True

                let _posted = msrt_http_group_post(group.get(), index, 0)
                continue

            if message == "STOP":
                let _posted = msrt_http_group_post(group.get(), index, 1)
                continue

            if message == "DONE":
                let _posted = msrt_http_group_post(group.get(), index, 2)
                return

            group_failure(group, errors, index, message)
            return

def member_control(server: Server) -> Unit:
    let member = server.member.get()

    while True:
        let message = msrt_http_member_read(member.get())

        if message.is_error():
            server.close_local()
            return

        let command = message.get().decode_utf8().get("")

        if command == "START":
            with var state_guard = lock(server.state):
                state_guard.value.released = True

            let waiting = server.state.get().start_waiter
            if waiting != 0: msrt_channel_post(waiting)
            continue

        server.close_local()
        return

def run_group_member(application: Callable[[Server], Result[Unit, HttpError]]) -> Unit:
    let acquired = msrt_http_member_take()
    if acquired.is_error(): return

    with let scope = MemberScope(share(acquired.get())):
        let member = scope.member
        let connected = msrt_http_member_connect(member.get())
        if connected.is_error(): return

        let identity = msrt_http_member_read(member.get())
        if identity.is_error(): return

        let fields = identity.get().decode_utf8().get("").split(":")
        if fields.length() != 2: return

        let index = parse[Int](fields[0])
        let count = parse[Int](fields[1])
        if index.is_error() or count.is_error(): return

        let encoded = msrt_http_member_read(member.get())
        if encoded.is_error(): return

        let options = parse[HttpServerOptions](encoded.get().decode_utf8().get(""))
        if options.is_error(): return

        let server = Server(
            "", options.get().clone(), member: some(member), member_index: index.get(),
            member_count: count.get()
        )
        var failure = ""

        with let controls = TaskGroup[Unit]():
            let controlled = server.clone()
            let _control = controls.spawn(lambda channel: member_control(controlled))
            let result = application(server.clone())
            if result.is_error(): failure = result.err().message()
            if not server.state.get().ready: failure = "application returned before server.run became ready"
            if not server.state.get().stopped: failure = "application returned before group shutdown"

        msrt_http_member_disarm(member.get())

        var outcome = "DONE"
        if failure != "": outcome = "ERROR: " + failure

        let _sent = msrt_http_member_write(member.get(), outcome.to_bytes())

def group_remaining(started: Instant, limit: Optional[Duration]) -> Int:
    if let budget = limit:
        let remaining = (
            budget.to_nanoseconds()
            - clock().now().difference(started).to_nanoseconds()
        )
        if remaining <= 0: return 0

        return remaining

    return -1

def group_drain_remaining(
    started: Instant,
    grace: Optional[Duration],
    cleanup: Duration
) -> Int:
    if let limit = grace:
        let elapsed = clock().now().difference(started).to_nanoseconds()
        let after_grace = elapsed - limit.to_nanoseconds()
        let final_budget = cleanup.to_nanoseconds()
        if after_grace >= final_budget: return 0
        if after_grace >= 0: return final_budget - after_grace

        let before_grace = 0 - after_grace
        if before_grace > 9223372036854775807 - final_budget: return 9223372036854775807

        return before_grace + final_budget

    return -1

def serve_group(
    address: String,
    application: Callable[[Server], Result[Unit, HttpError]],
    options: HttpServerOptions,
    execution: Execution
) -> Result[Unit, HttpError]:
    var processes = False
    var count: Optional[Int] = none
    var startup: Optional[Duration] = none
    var cleanup = 30.seconds

    match execution:
        case Workers(members, timeout):
            count = members
            startup = timeout
        case Processes(members, timeout, final_timeout):
            processes = True
            count = members
            startup = timeout
            cleanup = final_timeout
        case Local: return error(HttpError.InvalidInput)

    if let timeout = startup:
        if timeout.to_nanoseconds() < 0: return error(HttpError.InvalidInput)

    let encoded = stringify(options)
    if encoded.is_error(): return error(HttpError.InvalidInput)

    let started = clock().now()
    let runner: Callable[[], Unit] = lambda: run_group_member(application)
    let native = try msrt_http_group_new(
        network(), address, runner, encoded.get(), processes, count,
        cleanup.to_nanoseconds()
    )

    with let scope = GroupScope(share(native)):
        let group = scope.group
        let members = msrt_http_group_count(group.get())
        let errors = share(Map[Int, String]())
        var ready = 0
        var done = 0
        var stopping = False
        var draining = started
        let progress = share(GroupProgress(draining: started))

        with let controls = TaskGroup[Unit]():
            with let drain = GroupDrainScope(
                group, progress, members, options.grace, cleanup
            ):
                for index in range(0, members):
                    try msrt_http_group_spawn(group.get(), index)

                    let _watch = controls.spawn(
                        lambda channel: watch_group_member(
                            group, errors, index
                        )
                    )

                while done < members:
                    var remaining = -1
                    if ready < members: remaining = group_remaining(started, startup)
                    if stopping: remaining = group_drain_remaining(
                        draining, options.grace, cleanup
                    )

                    let event = msrt_http_group_next(group.get(), remaining)
                    if event < 0: return error(HttpError.Timeout)

                    let index = event / 16
                    let kind = event % 16
                    if kind == 3:
                        return error(
                            HttpError.Failed(
                                f"member {index}: {errors.get().get(index).get("control channel failed")}"
                            )
                        )

                    if kind == 0:
                        ready += 1
                        with var update_guard = lock(progress):
                            update_guard.value.ready = ready
                        if ready == members:
                            for member_index in range(0, members):
                                try msrt_http_group_write(
                                    group.get(), member_index, "START".to_bytes()
                                )
                        continue

                    if kind == 1 and not stopping:
                        if ready != members: return error(HttpError.Closed)

                        stopping = True
                        draining = clock().now()

                        with var update_guard = lock(progress):
                            update_guard.value.stopping = True
                            update_guard.value.draining = draining

                        for member_index in range(0, members):
                            try msrt_http_group_write(
                                group.get(), member_index, "STOP".to_bytes()
                            )
                        continue

                    if kind == 2:
                        if not stopping: return error(
                            HttpError.Failed(
                                f"member {index}: unexpected application completion"
                            )
                        )

                        done += 1
                        with var update_guard = lock(progress):
                            update_guard.value.done = done

            let waited = controls.wait()
            if waited.is_error(): return error(HttpError.Failed(waited.err().message()))

        let joining = clock().now()

        for index in range(0, members):
            var remaining = group_drain_remaining(draining, options.grace, cleanup)
            if remaining < 0: remaining = group_remaining(joining, some(cleanup))
            try msrt_http_group_join(group.get(), index, remaining)

    return ok(())
