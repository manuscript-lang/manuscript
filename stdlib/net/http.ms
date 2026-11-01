import Closeable, Data from "@std/core.ms"
import Bytes, join from "@std/bytes.ms"
import Duration from "@std/os/time.ms"
import IoError from "@std/io/io.ms"
import stringify from "@std/data/json.ms"
import ReadStream from "@std/io/io.ms"
import TlsOptions from "@std/net/net.ms"
import WebSocket from "@std/net/net.ms"
import WebSocketError from "@std/net/net.ms"

extern fn msrt_http_headers_append(
    headers: HttpHeaders,
    name: String,
    value: Bytes
) Unit!HttpError

extern fn msrt_http_headers_values(value: HttpHeaders, name: String) List[Bytes]?

extern fn msrt_http_headers_names(value: HttpHeaders) List[String]

extern fn msrt_http_headers_remove(value: HttpHeaders, name: String) Bool

extern fn msrt_http_headers_clone(value: HttpHeaders) HttpHeaders

extern fn msrt_http_headers_new() HttpHeaders

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

# Mutable HTTP fields with ASCII case-insensitive names and separate values, which are Strings by default and Bytes on request.
# Names keep first-insertion order and spelling; values keep append order.
# Headers are an owned value: assignment moves them, mutation needs `var`, and clone() copies them.
export extern type HttpHeaders

impl HttpHeaders:
    # Appends a String value under a valid HTTP name; invalid names return InvalidInput.
    # Transport operations additionally validate framing and field values.
    var fn append(name: String, value: String) Unit!HttpError:
        return msrt_http_headers_append(self, name, value.to_bytes())

    # Appends raw bytes, for the rare field whose value is not UTF-8 text.
    var fn append_bytes(name: String, value: Bytes) Unit!HttpError:
        return msrt_http_headers_append(self, name, value)

    # Returns every value as an owned list, empty for an absent name.
    # A received value that is not valid UTF-8 is left out; read it with values_bytes.
    fn values(name: String) List[String]:
        var out: List[String] = []
        let raw = msrt_http_headers_values(self, name)
        if let found = raw:
            for item in found:
                if let text = item.decode_utf8(): out.append(text)
        return out

    # Returns the raw bytes of every value as an owned list, or none for an absent name.
    fn values_bytes(name: String) List[Bytes]?:
        return msrt_http_headers_values(self, name)

    # Reports whether the name has any value, whatever its encoding.
    fn contains(name: String) Bool:
        return msrt_http_headers_values(self, name).is_some()

    # Returns first-inserted spellings in insertion order.
    fn names() List[String]:
        return msrt_http_headers_names(self)

    # Removes a name; existing list aliases are detached from this header object.
    var fn remove(name: String) Bool:
        return msrt_http_headers_remove(self, name)

    # Copies name/list membership and shares immutable Bytes values.
    fn clone() HttpHeaders:
        return msrt_http_headers_clone(self)

# Creates empty mutable headers. No header values are joined or comma-combined.
export fn headers() HttpHeaders:
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
    fn metadata() HttpResponseMetadata:
        return self.head.clone()

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
    fn text() String:
        match self:
            Get: return "GET"
            Head: return "HEAD"
            Post: return "POST"
            Put: return "PUT"
            Patch: return "PATCH"
            Delete: return "DELETE"
            Connect: return "CONNECT"
            Options: return "OPTIONS"
            Trace: return "TRACE"
            Custom(value): return value.clone()

# The runtime handle behind a `HttpClient`.
export extern type NativeHttpClient

extern fn msrt_http_client_close(handle: NativeHttpClient) Unit

extern fn msrt_http_client_request(
    handle: NativeHttpClient,
    method: HttpMethod,
    url: String,
    headers: HttpHeaders,
    body: String,
    max_response_bytes: Int?,
    timeout: Duration?
) ResponseBody!HttpError

extern fn msrt_http_client_request_bytes(
    handle: NativeHttpClient,
    method: HttpMethod,
    url: String,
    headers: HttpHeaders,
    body: Bytes,
    max_response_bytes: Int?,
    timeout: Duration?
) ResponseBody!HttpError

extern fn msrt_http_client_request_stream(
    handle: NativeHttpClient,
    method: HttpMethod,
    url: String,
    headers: HttpHeaders,
    body: ReadStream,
    max_response_bytes: Int?,
    timeout: Duration?
) ResponseBody!HttpError

# Reusable HTTP client with connection pooling and explicit response limits.
# Outbound headers retain separate values in their stored order.
export type HttpClient:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeHttpClient

impl Closeable for HttpClient:
    # Cancels in-flight requests, closes open response bodies, and drops idle pooled connections.
    # Safe to call repeatedly; later requests return Closed.
    var fn close() Unit!:
        msrt_http_client_close(self.native)
        return ok(unit)

impl HttpClient:
    # Sends the UTF-8 text body and returns a scoped streaming response body.
    fn request(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: String = "",
        max_response_bytes: Int?,
        timeout: Duration?
    ) ResponseBody!HttpError:
        return msrt_http_client_request(
            self.native, method, url, headers, body, max_response_bytes, timeout
        )

    # Sends immutable Bytes and returns a scoped streaming response body.
    fn request_bytes(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: Bytes = "".to_bytes(),
        max_response_bytes: Int?,
        timeout: Duration?
    ) ResponseBody!HttpError:
        return msrt_http_client_request_bytes(
            self.native, method, url, headers, body, max_response_bytes, timeout
        )

    # Borrows ReadStream upload data through the scoped response lifetime.
    fn request_stream(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: ReadStream,
        max_response_bytes: Int?,
        timeout: Duration?
    ) ResponseBody!HttpError:
        return msrt_http_client_request_stream(
            self.native, method, url, headers, body, max_response_bytes, timeout
        )

# Connection, redirect, cookie, decompression, and TLS settings for an HTTP client.
export type HttpClientOptions:
    # Most redirects followed per request. 0 returns the redirect response itself, none sets no cap, and a negative count is rejected.
    # Redirects that downgrade from HTTPS, leave the network's restrictions, or carry user info are refused.
    max_redirects: Int?
    # Number of idle connections kept for reuse. Must be nonnegative; none sets no explicit cap.
    max_idle_connections: Int?
    # Largest accepted size of a response header block, in bytes. Must be positive; none uses the default of 1 MiB.
    max_header_bytes: Int?
    # How long an idle pooled connection is kept before it is closed. none never expires it, and a negative duration is rejected.
    idle_timeout: Duration?
    # When True, gzip-encoded responses are decoded transparently, with `max_response_bytes` bounding the decoded size; when False (the default), bodies arrive exactly as sent.
    decompress: Bool = false
    # When True, the client keeps an in-memory cookie jar for its lifetime, respecting public-suffix boundaries; when False (the default), no cookies are stored or sent automatically.
    cookies: Bool = false
    # TLS trust and client-certificate settings for `https` requests. The host name is taken from each URL, so `server_name` is ignored.
    tls: TlsOptions = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "",
        alpn: [], require_client_certificate: false
    )

# One streaming server exchange. Read or write incrementally and close when done.
# Received headers are an owned copy; repeated values stay separate.
export interface HttpExchange:
    # Ends the exchange, interrupting reads or writes in progress.
    # Later operations return Closed.
    var fn close() Unit
    # Returns an owned copy of the request headers with every repeated value retained.
    fn headers() HttpHeaders
    # Returns the request method, using the Custom case for extension tokens.
    fn method() HttpMethod
    # Returns the percent-decoded request path with dot segments resolved.
    # Requests with an encoded slash or NUL are rejected before the handler runs.
    fn path() String
    # Returns the protocol the request arrived over, such as `HTTP/1.1` or `HTTP/2.0`.
    fn protocol() String
    # Returns the raw query string without the leading `?`; it is empty when there is none.
    fn query() String
    # Returns the next chunk of the request body, at most `max_bytes` and never more than 65536, or none at the end of the body.
    # Reading past `max_body_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.
    var fn read(max_bytes: Int?) Bytes?!IoError
    # Sends a whole response: the status line, `headers`, and `body` with its length known, so the response carries `Content-Length` rather than chunked framing. Requests with HEAD and statuses without a body get the head alone.
    # The rules of `send_headers` apply, `body` is bounded by `max_response_bytes`, and nothing else may be sent afterwards.
    var fn send(status: Int, headers: HttpHeaders, body: Bytes) Unit!HttpError
    # Sends the status line and headers once, before any body is written.
    # The status must be 200 through 599, header names cannot be `Content-Length`, `Transfer-Encoding`, or `Connection`, and header bytes are bounded by `max_header_bytes`. A second call returns InvalidInput and a closed exchange returns Closed.
    var fn send_headers(status: Int, headers: HttpHeaders) Unit!HttpError
    # Switches the connection to a WebSocket after checking the `Origin` header. Requests without an Origin are accepted; otherwise it must exactly match an entry of `allowed_origins`, or, when that list is empty, match the request's own scheme and host.
    # `subprotocols` lists the protocols the server accepts, and `max_message_bytes` must be positive when given. An exchange that already sent headers or upgraded returns InvalidInput, and a request that is not a valid WebSocket upgrade returns Failed.
    var fn upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Int?
    ) WebSocket!WebSocketError
    # Writes one chunk of the response body and flushes it.
    # `send_headers` must come first, and writing beyond `max_response_bytes` returns IoError.Failed. Responses to HEAD requests and with status 204 or 304 cannot have a body.
    var fn write(data: String) Unit!IoError
    # Writes one chunk of raw bytes with the same rules as write.
    var fn write_bytes(data: Bytes) Unit!IoError

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

# The runtime handle behind a `HttpServer`.
export extern type NativeHttpServer

extern fn msrt_http_server_address(handle: NativeHttpServer) String

extern fn msrt_http_server_adopt(handle: NativeHttpServer, connection: Int) Unit

extern fn msrt_http_server_close(handle: NativeHttpServer) Unit

extern fn msrt_http_server_wait(handle: NativeHttpServer) Unit!IoError

# A running HTTP server. Close it to stop accepting new requests.
export type HttpServer:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeHttpServer

impl Closeable for HttpServer:
    # Stops accepting connections, waits up to the grace period for in-flight requests, then cancels the rest and waits for them.
    # SIGINT/SIGTERM drains the same way when grace is nonzero: in-flight requests finish within the grace period before the program exits 130/143.
    # Safe to call repeatedly. A request handler calling close on its own server faults, and a shutdown error is raised as a fault.
    var fn close() Unit!:
        msrt_http_server_close(self.native)
        return ok(unit)

impl HttpServer:
    # Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.
    fn address() String:
        return msrt_http_server_address(self.native)

    # Serves the socket handle `Listener.accept_raw` returned, on the thread that started this server. The server owns the socket from here, also when it is closing and drops the connection. Use each handle once.
    fn adopt(connection: Int) Unit:
        msrt_http_server_adopt(self.native, connection)

    # Blocks until the server stops. Returns Ok after a normal `close`, or IoError.Failed with the host's text if serving ended with an error.
    # Cancelling the waiting task stops the wait.
    fn wait() Unit!IoError:
        return msrt_http_server_wait(self.native)

# Request and response limits, deadlines, graceful shutdown, and TLS server settings.
export type HttpServerOptions:
    # Most requests handled at once; further requests are answered with 503. Must be positive; none sets no cap.
    max_requests: Int?
    # Largest accepted request body, in bytes. Must be nonnegative; none sets no cap.
    max_body_bytes: Int?
    # Most response body bytes a handler may write, in bytes. Must be nonnegative; none sets no cap.
    max_response_bytes: Int?
    # Largest accepted request header block and largest response header block, in bytes. Must be positive; none uses the default of 1 MiB.
    max_header_bytes: Int?
    # Per-request time budget covering reading the request, running the handler, and writing the response; an idle plain-HTTP connection waiting for its next request is also closed after it. A handler still running at the deadline is cancelled (`tasks.cancelled()` turns true and its waits end) and the request is answered 504; a WebSocket it opened is not limited. Must be positive; none sets no deadline.
    timeout: Duration?
    # How long `close` waits for in-flight requests to finish before cancelling them. none waits without limit and 0 cancels immediately.
    grace: Duration?
    # Some(options) serves HTTPS and negotiates HTTP/2 or HTTP/1.1 through ALPN; none, the default, serves plain HTTP/1.1.
    tls: TlsOptions?

# The runtime handle behind a `ResponseBody`.
export extern type NativeResponseBody

extern fn msrt_http_body_close(handle: NativeResponseBody) Unit

extern fn msrt_http_body_metadata(handle: NativeResponseBody) HttpResponseMetadata

extern fn msrt_http_body_read(
    handle: NativeResponseBody,
    max_bytes: Int?
) Bytes?!IoError

extern fn msrt_http_body_read_all(handle: NativeResponseBody) Bytes!IoError

# Streaming response body returned by reusable HTTP client operations.
# Metadata remains available after close and shares one mutable header object.
export type ResponseBody:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeResponseBody

impl Closeable for ResponseBody:
    # Cancels the rest of the response and releases its connection.
    # Safe to call repeatedly; reads afterwards return Closed. A fully read body lets the connection be reused.
    var fn close() Unit!:
        msrt_http_body_close(self.native)
        return ok(unit)

impl ResponseBody:
    # Returns the response head (status and headers) without copying; it stays available after close.
    fn metadata() HttpResponseMetadata:
        return msrt_http_body_metadata(self.native)

    # Returns the next chunk of the response body, at most `max_bytes` and never more than 65536, or none at the end of the body.
    # Reading past the request's `max_response_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.
    fn read(max_bytes: Int?) Bytes?!IoError:
        return msrt_http_body_read(self.native, max_bytes)

    # Reads the rest of the body into one value, with `read`'s limit and error rules.
    # A plain HTTP/1.1 body of known length arrives straight into the result without intermediate copies.
    fn read_all() Bytes!IoError:
        return msrt_http_body_read_all(self.native)

# Maps a stream failure to the HTTP error with the same meaning, so exchange handlers need one error type.
export fn from_io(error: IoError) HttpError:
    match error:
        Closed: return HttpError.Closed
        InvalidInput: return HttpError.InvalidInput
        InvalidData: return HttpError.InvalidData
        LimitExceeded: return HttpError.LimitExceeded
        Unavailable: return HttpError.Failed("HTTP: unavailable")
        Failed(message): return HttpError.Failed(message.clone())

# Reads the rest of the request body into one value.
# A body over `max_body_bytes` of the server's options returns LimitExceeded; `limit` also bounds it when given.
export fn read_body(var exchange: HttpExchange, limit: Int?) Bytes!HttpError:
    let first = try exchange.read().map_error(from_io)
    if let head = first:
        return read_rest(var exchange, head, limit)

    return ok("".to_bytes())

# Joins `head` with the chunks after it. A body that fits one chunk is returned without copying.
fn read_rest(var exchange: HttpExchange, head: Bytes, limit: Int?) Bytes!HttpError:
    var total = head.length()
    if over_limit(total, limit): return error(HttpError.LimitExceeded)

    let second = try exchange.read().map_error(from_io)

    if let next = second:
        total += next.length()
        if over_limit(total, limit): return error(HttpError.LimitExceeded)

        return read_more(var exchange, [head, next], total, limit)

    return ok(head)

fn read_more(var exchange: HttpExchange, chunks: List[Bytes], total: Int, limit: Int?) Bytes!HttpError:
    var parts = chunks
    var size = total

    while true:
        let chunk = try exchange.read().map_error(from_io)

        if let bytes = chunk:
            size += bytes.length()
            if over_limit(size, limit): return error(HttpError.LimitExceeded)

            parts.append(bytes)
        else:
            return ok(join(parts))

fn over_limit(total: Int, limit: Int?) Bool:
    if let max = limit:
        return total > max

    return false

# Sends `response` whole: its status and headers, then its body.
export fn reply(var exchange: HttpExchange, response: HttpResponse) Unit!HttpError:
    return exchange.send(response.status, response.headers, response.body)

# Builds a response with a UTF-8 text body and no headers.
export fn text(status: Int, body: String) HttpResponse:
    return HttpResponse(status: status, headers: headers(), body: body.to_bytes())

# Builds a response whose body is `value` encoded as JSON, with `Content-Type: application/json`.
# A value `stringify` cannot encode returns Failed with its diagnostic.
export fn json[T: Data](status: Int, value: T) HttpResponse!HttpError:
    let body = stringify(value)
    if body.is_error(): return error(HttpError.Failed(body.err().message()))

    var sent = headers()
    try sent.append("Content-Type", "application/json")
    return ok(HttpResponse(status: status, headers: sent, body: body.get().to_bytes()))

# Builds a redirect to `location` with an empty body.
# The status should be 301, 302, 303, 307, or 308; the default 303 sends a followed POST on as a GET.
export fn redirect(location: String, status: Int = 303) HttpResponse!HttpError:
    var sent = headers()
    try sent.append("Location", location)
    return ok(HttpResponse(status: status, headers: sent, body: "".to_bytes()))

# Adapts a handler that maps a whole request to a whole response into an exchange handler for `serve`.
# The request body is read in full first.
export fn buffered(
    handler: fn(HttpRequest) HttpResponse
) fn(var HttpExchange) Unit!HttpError:
    return fn var exchange: serve_buffered(handler, var exchange)

fn serve_buffered(
    handler: fn(HttpRequest) HttpResponse,
    var exchange: HttpExchange
) Unit!HttpError:
    let body = try read_body(var exchange)
    let request = HttpRequest(
        method: exchange.method(), path: exchange.path(), query: exchange.query(),
        headers: exchange.headers(), body: body, protocol: exchange.protocol()
    )
    return reply(var exchange, handler(request))

impl Error for HttpError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `HTTP: <reason>`.
    fn message() String:
        match self:
            InvalidInput: return "HTTP: invalid input"
            InvalidData: return "HTTP: invalid data"
            LimitExceeded: return "HTTP: limit exceeded"
            PermissionDenied: return "HTTP: permission denied"
            Closed: return "HTTP: resource is closed"
            Timeout: return "HTTP: operation timed out"
            Failed(message): return message.clone()
