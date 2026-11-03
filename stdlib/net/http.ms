import Closeable, Data from "@std/core.ms"
import Bytes, join from "@std/bytes.ms"
import Duration from "@std/os/time.ms"
import Promise, deferred, complete from "@std/concurrency/promise.ms"
import stringify from "@std/data/json.ms"
import ReadStream, WriteStream, Source, Sink, stream, writer from "@std/io/io.ms"
import TlsOptions from "@std/net/net.ms"
import WebSocket, RawWebSocket, web_socket_from from "@std/net/net.ms"
import (
    msstd_http_client_close,
    msstd_http_headers_append,
    msstd_http_headers_values,
    msstd_http_headers_names,
    msstd_http_headers_remove,
    msstd_http_headers_clone,
    msstd_http_headers_new,
    msstd_http_client_request,
    msstd_http_client_request_bytes,
    msstd_http_body_close,
    msstd_http_body_metadata,
    msstd_http_body_read,
    msstd_http_body_read_all
) from "@std/internal/http.ms"

/*
Mutable HTTP fields with ASCII case-insensitive names and separate values, which are Strings by default and Bytes on request.
Names keep first-insertion order and spelling; values keep append order.
Headers are an owned value: assignment moves them, mutation needs `var`, and clone() copies them.
*/
export extern type HttpHeaders

impl HttpHeaders:
    // Appends a String value under a valid HTTP name; invalid names return InvalidInput.
    // Transport operations additionally validate framing and field values.
    var fn append(name: String, value: String) Unit!:
        return msstd_http_headers_append(self, name, value.to_bytes())

    // Appends raw bytes, for the rare field whose value is not UTF-8 text.
    var fn append_bytes(name: String, value: Bytes) Unit!:
        return msstd_http_headers_append(self, name, value)

    // Returns every value as an owned list, empty for an absent name.
    // A received value that is not valid UTF-8 is left out; read it with values_bytes.
    fn values(name: String) List[String]:
        var out: List[String] = []
        let raw = msstd_http_headers_values(self, name)
        if let found = raw:
            for item in found:
                if let text = item.decode_utf8(): out.append(text)
        return out

    // Returns the raw bytes of every value as an owned list, or none for an absent name.
    fn values_bytes(name: String) List[Bytes]?:
        return msstd_http_headers_values(self, name)

    // Reports whether the name has any value, whatever its encoding.
    fn contains(name: String) Bool:
        return msstd_http_headers_values(self, name).is_some()

    // Returns first-inserted spellings in insertion order.
    fn names() List[String]:
        return msstd_http_headers_names(self)

    // Removes a name; existing list aliases are detached from this header object.
    var fn remove(name: String) Bool:
        return msstd_http_headers_remove(self, name)

    // Copies name/list membership and shares immutable Bytes values.
    fn clone() HttpHeaders:
        return msstd_http_headers_clone(self)

// Creates empty mutable headers. No header values are joined or comma-combined.
export fn headers() HttpHeaders:
    return msstd_http_headers_new()

// Response status and headers shared by buffered and streaming response access.
export type HttpResponseMetadata:
    // The received status; editing metadata leaves wire/body behavior unchanged.
    status: Int
    // The header fields, with every repeated value retained.
    headers: HttpHeaders
    // The protocol the response used, such as `HTTP/1.1` or `HTTP/2.0`; empty when the source does not report one.
    protocol: String = ""

// Buffered response body with explicit common metadata access.
export type ClientResponse:
    // Response metadata; changing it requires a mutable response and no live borrow of head.
    head: HttpResponseMetadata
    // The complete response payload within the supplied byte bound.
    body: Bytes

impl ClientResponse:
    // Borrows the current response metadata.
    // Clone the result for an independent owned value, including its headers.
    fn metadata() HttpResponseMetadata:
        return self.head.clone()

// Known HTTP methods, plus extension tokens validated by outgoing operations.
export type HttpMethod:
    // Requests the selected representation.
    case Get
    // Requests response metadata without a body.
    case Head
    // Submits a representation for processing.
    case Post
    // Replaces the selected representation.
    case Put
    // Applies a partial modification.
    case Patch
    // Removes the selected representation.
    case Delete
    // Establishes a tunnel to the request target.
    case Connect
    // Asks which communication options the target supports, without transferring a body.
    case Options
    // Requests a diagnostic loopback.
    case Trace
    // Carries an extension token; requests reject empty or malformed tokens.
    case Custom(
        // The method token; it must be a non-empty HTTP token such as PURGE.
        value: String
    )

impl HttpMethod:
    // Returns the method token; outgoing requests reject malformed Custom tokens.
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

// The runtime handle behind a `HttpClient`.
export extern type NativeHttpClient

// Reusable HTTP client with connection pooling and explicit response limits.
// Outbound headers retain separate values in their stored order.
export type HttpClient:
    // The runtime handle; it is released by `close` and owned by this value.
    native: NativeHttpClient

impl Closeable for HttpClient:
    // Cancels in-flight requests, closes open response bodies, and drops idle pooled connections.
    // Safe to call repeatedly; later requests return Closed.
    var fn close() Unit!:
        msstd_http_client_close(self.native)
        return ok(unit)

impl HttpClient:
    // Sends the UTF-8 text body and returns the response with its body as a stream.
    fn request(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: String = "",
        max_response_bytes: Int?,
        timeout: Duration?
    ) StreamingResponse!:
        let raw = try msstd_http_client_request(
            self.native, method, url, headers, body, max_response_bytes, timeout
        )
        return ok(response(raw))

    // Sends immutable Bytes and returns the response with its body as a stream.
    fn request_bytes(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: Bytes = "".to_bytes(),
        max_response_bytes: Int?,
        timeout: Duration?
    ) StreamingResponse!:
        let raw = try self.request_raw(
            method, url, headers, body, max_response_bytes, timeout
        )
        return ok(response(raw))

    // Sends immutable Bytes and returns the native response, for callers that buffer the whole body.
    fn request_raw(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: Bytes,
        max_response_bytes: Int?,
        timeout: Duration?
    ) RawResponse!:
        return msstd_http_client_request_bytes(
            self.native, method, url, headers, body, max_response_bytes, timeout
        )

    // Reads `body` to its end, then sends it as the request body. The upload is buffered until the request can
    // return a `WriteStream` for the body to be written into.
    fn request_stream(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: ReadStream[Bytes],
        max_response_bytes: Int?,
        timeout: Duration?
    ) StreamingResponse!:
        var input = body
        var chunks: List[Bytes] = []

        while true:
            let chunk = try input.read().wait()

            if let bytes = chunk:
                chunks.append(bytes)
            else:
                break

        try input.close()
        return self.request_bytes(
            method, url, headers, join(chunks), max_response_bytes, timeout
        )

// Connection, redirect, cookie, decompression, and TLS settings for an HTTP client.
export type HttpClientOptions:
    // Most redirects followed per request. 0 returns the redirect response itself, none sets no cap, and a negative count is rejected.
    // Redirects that downgrade from HTTPS, leave the network's restrictions, or carry user info are refused.
    max_redirects: Int?
    // Number of idle connections kept for reuse. Must be nonnegative; none sets no explicit cap.
    max_idle_connections: Int?
    // Largest accepted size of a response header block, in bytes. Must be positive; none uses the default of 1 MiB.
    max_header_bytes: Int?
    // How long an idle pooled connection is kept before it is closed. none never expires it, and a negative duration is rejected.
    idle_timeout: Duration?
    // When True, gzip-encoded responses are decoded transparently, with `max_response_bytes` bounding the decoded size; when False (the default), bodies arrive exactly as sent.
    decompress: Bool = false
    // When True, the client keeps an in-memory cookie jar for its lifetime, respecting public-suffix boundaries; when False (the default), no cookies are stored or sent automatically.
    cookies: Bool = false
    // TLS trust and client-certificate settings for `https` requests. The host name is taken from each URL, so `server_name` is ignored.
    tls: TlsOptions = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "",
        alpn: [], require_client_certificate: false
    )

// One streaming server exchange. Read or write incrementally and close when done.
// Received headers are an owned copy; repeated values stay separate.
export interface HttpExchange:
    // Ends the exchange, interrupting reads or writes in progress.
    // Later operations return Closed.
    var fn close() Unit
    // Returns an owned copy of the request headers with every repeated value retained.
    fn headers() HttpHeaders
    // Returns the request method, using the Custom case for extension tokens.
    fn method() HttpMethod
    // Returns the percent-decoded request path with dot segments resolved.
    // Requests with an encoded slash or NUL are rejected before the handler runs.
    fn path() String
    // Returns the protocol the request arrived over, such as `HTTP/1.1` or `HTTP/2.0`.
    fn protocol() String
    // Returns the raw query string without the leading `?`; it is empty when there is none.
    fn query() String
    // Returns the next chunk of the request body, at most `max_bytes` and never more than 65536, or none at the end of the body.
    // Reading past `max_body_bytes` returns an `Error` of kind `Failed`, and a non-positive `max_bytes` returns InvalidInput.
    var fn read(max_bytes: Int?) Bytes?!
    // Sends a whole response: the status line, `headers`, and `body` with its length known, so the response carries `Content-Length` rather than chunked framing. Requests with HEAD and statuses without a body get the head alone.
    // The rules of `send_headers` apply, `body` is bounded by `max_response_bytes`, and nothing else may be sent afterwards.
    var fn send(status: Int, headers: HttpHeaders, body: Bytes) Unit!
    // Sends the status line and headers once, before any body is written.
    // The status must be 200 through 599, header names cannot be `Content-Length`, `Transfer-Encoding`, or `Connection`, and header bytes are bounded by `max_header_bytes`. A second call returns InvalidInput and a closed exchange returns Closed.
    var fn send_headers(status: Int, headers: HttpHeaders) Unit!
    // Switches the connection to a WebSocket after checking the `Origin` header. Requests without an Origin are accepted; otherwise it must exactly match an entry of `allowed_origins`, or, when that list is empty, match the request's own scheme and host.
    // `subprotocols` lists the protocols the server accepts, and `max_message_bytes` must be positive when given. An exchange that already sent headers or upgraded returns InvalidInput, and a request that is not a valid WebSocket upgrade returns Failed.
    var fn upgrade(
        allowed_origins: List[String],
        subprotocols: List[String],
        max_message_bytes: Int?
    ) RawWebSocket!
    // Writes one chunk of the response body and flushes it.
    // `send_headers` must come first, and writing beyond `max_response_bytes` returns an `Error` of kind `Failed`. A write on a HEAD request succeeds and drops the bytes, so a handler written for GET needs no HEAD case; statuses 204 and 304 cannot have a body and return InvalidInput.
    var fn write(data: String) Unit!
    // Writes one chunk of raw bytes with the same rules as write.
    var fn write_bytes(data: Bytes) Unit!

// Buffered request accepted by the simple HTTP server handler.
export type HttpRequest:
    // The request method, using the Custom case for extension tokens.
    method: HttpMethod
    // The percent-decoded request path with dot segments resolved, so `/a/../b` arrives as `/b`.
    path: String
    // The raw query string without the leading `?`; empty when there is none.
    query: String
    // The request headers as mutable fields with every repeated value retained.
    headers: HttpHeaders
    // The complete request body, at most `max_body_bytes` long.
    body: Bytes
    // The protocol the request arrived over, such as `HTTP/1.1` or `HTTP/2.0`; empty when not reported.
    protocol: String = ""

// Buffered response returned by the simple HTTP server handler.
export type HttpResponse:
    // The HTTP status code, which must be 200 through 599; other values are answered with a 500 error.
    status: Int
    // The response headers to send; `Content-Length`, `Transfer-Encoding`, and `Connection` are rejected with a 500 error.
    headers: HttpHeaders
    // The response body bytes, which must not exceed `max_response_bytes`; the server sets the content length.
    body: Bytes

// The listener, handler, limits, TLS settings and admission count that every connection of one `serve` call shares.
export extern type NativeServing

// One worker thread's HTTP engine: the connections it adopted, driven by the poller without a task each.
export extern type NativeWorker

// A running HTTP server. Close it, or drop it, to stop accepting and drain.
export type HttpServer:
    // The accept loop, which owns the connection promises. It is declared first so it ends before what it uses.
    accepting: Promise[Unit]
    // The bound local address as `host:port`.
    bound: String
    // Whether `close` has been called, so `wait` reports a normal stop.
    stopped: Bool

impl Closeable for HttpServer:
    // Stops accepting and asks every connection to finish: idle ones close at once, requests in flight finish within `grace`, then the rest are cancelled. It returns without waiting; `wait` or dropping the server joins. Safe to call repeatedly.
    var fn close() Unit!:
        self.stopped = true

        let _ = self.accepting.wait(timeout: 0.seconds)
        return ok(unit)

impl HttpServer:
    // Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.
    fn address() String:
        return self.bound.clone()

    // Waits until the server has stopped. Returns Ok after `close`, or the error that ended accepting (`Failed` with the host's text). `timeout` bounds the wait and cancels the server when it passes.
    fn wait(timeout: Duration? = none) Unit!:
        let ended = self.accepting.wait(timeout)
        if self.stopped:
            return ok(unit)

        return ended

// Request and response limits, deadlines, graceful shutdown, and TLS server settings.
export type HttpServerOptions:
    // Most requests handled at once; further requests are answered with 503. Must be positive; none sets no cap.
    max_requests: Int?
    // Largest accepted request body, in bytes. Must be nonnegative; none sets no cap.
    max_body_bytes: Int?
    // Most response body bytes a handler may write, in bytes. Must be nonnegative; none sets no cap.
    max_response_bytes: Int?
    // Largest accepted request header block and largest response header block, in bytes. Must be positive; none uses the default of 1 MiB.
    max_header_bytes: Int?
    // Per-request time budget covering reading the request, running the handler, and writing the response; an idle plain-HTTP connection waiting for its next request is also closed after it. A handler still running at the deadline is cancelled (`tasks.cancelled()` turns true and its waits end) and the request is answered 504; a WebSocket it opened is not limited. Must be positive; none sets no deadline.
    timeout: Duration?
    // How long `close` waits for in-flight requests to finish before cancelling them. none waits without limit and 0 cancels immediately.
    grace: Duration?
    // Some(options) serves HTTPS and negotiates HTTP/2 or HTTP/1.1 through ALPN; none, the default, serves plain HTTP/1.1.
    tls: TlsOptions?
    // How many threads serve connections: the runtime starts at most this many scheduler threads. Must be at least 1; none uses every core.
    cores: Int?

// The runtime handle behind a `RawResponse`.
export extern type NativeResponseBody

// The native response a client operation returns: its body is read through `StreamingResponse.body`.
// Metadata remains available after close and shares one mutable header object.
export type RawResponse:
    // The runtime handle; it is released by `close` and owned by this value.
    native: NativeResponseBody

impl Closeable for RawResponse:
    // Cancels the rest of the response and releases its connection.
    // Safe to call repeatedly; reads afterwards return Closed. A fully read body lets the connection be reused.
    var fn close() Unit!:
        msstd_http_body_close(self.native)
        return ok(unit)

impl RawResponse:
    // Returns the response head (status and headers) without copying; it stays available after close.
    fn metadata() HttpResponseMetadata:
        return msstd_http_body_metadata(self.native)

    // Reads the rest of the body into one value, bounded by the request's `max_response_bytes`.
    // A plain HTTP/1.1 body of known length arrives straight into the result without intermediate copies.
    fn read_all() Bytes!:
        return msstd_http_body_read_all(self.native)

// A client response: the head and the body as a stream. Closing or dropping the body cancels the rest of the
// response and releases its connection; a fully read body lets the connection be reused.
export type StreamingResponse:
    // Status and headers, available whether or not the body is read.
    metadata: HttpResponseMetadata
    // The body, at most 64 KiB per item. Reading past the request's `max_response_bytes` is an `Error` of kind `Failed`.
    body: ReadStream[Bytes]

impl Closeable for StreamingResponse:
    // Closes the body, which cancels what is unread and releases the connection.
    var fn close() Unit!:
        return self.body.close()

type ResponseSource:
    raw: RawResponse

impl Source[Bytes] for ResponseSource:
    var fn next() Bytes?!:
        return msstd_http_body_read(self.raw.native, none)

    var fn close() Unit!:
        return self.raw.close()

fn response(raw: RawResponse) StreamingResponse:
    let metadata = raw.metadata()
    return StreamingResponse(
        metadata: metadata, body: stream[Bytes](ResponseSource(raw))
    )

// Reads the rest of the request body into one value.
// A body over `max_body_bytes` of the server's options returns LimitExceeded; `limit` also bounds it when given.
export fn read_body(var exchange: HttpExchange, limit: Int?) Bytes!:
    let first = try exchange.read()
    if let head = first:
        return read_rest(var exchange, head, limit)

    return ok("".to_bytes())

// Joins `head` with the chunks after it. A body that fits one chunk is returned without copying.
fn read_rest(var exchange: HttpExchange, head: Bytes, limit: Int?) Bytes!:
    var total = head.length()
    if over_limit(total, limit): return error(
        Error("HTTP: limit exceeded", kind: LimitExceeded)
    )

    let second = try exchange.read()

    if let next = second:
        total += next.length()
        if over_limit(total, limit): return error(
            Error("HTTP: limit exceeded", kind: LimitExceeded)
        )

        return read_more(var exchange, [head, next], total, limit)

    return ok(head)

fn read_more(var exchange: HttpExchange, chunks: List[Bytes], total: Int, limit: Int?) Bytes!:
    var parts = chunks
    var size = total

    while true:
        let chunk = try exchange.read()

        if let bytes = chunk:
            size += bytes.length()
            if over_limit(size, limit): return error(
                Error("HTTP: limit exceeded", kind: LimitExceeded)
            )

            parts.append(bytes)
        else:
            return ok(join(parts))

fn over_limit(total: Int, limit: Int?) Bool:
    if let max = limit:
        return total > max

    return false

// Sends `response` whole: its status and headers, then its body.
export fn reply(var exchange: HttpExchange, response: HttpResponse) Unit!:
    return exchange.send(response.status, response.headers, response.body)

// Builds a response with a UTF-8 text body and no headers.
export fn text(status: Int, body: String) HttpResponse:
    return HttpResponse(status: status, headers: headers(), body: body.to_bytes())

// Builds a response whose body is `value` encoded as JSON, with `Content-Type: application/json`.
// A value `stringify` cannot encode returns Failed with its diagnostic.
export fn json[T: Data](status: Int, value: T) HttpResponse!:
    let body = stringify(value)
    if body.is_error(): return error(Error(body.err().message, kind: Failed))

    var sent = headers()
    try sent.append("Content-Type", "application/json")
    return ok(HttpResponse(status: status, headers: sent, body: body.get().to_bytes()))

// Builds a redirect to `location` with an empty body.
// The status should be 301, 302, 303, 307, or 308; the default 303 sends a followed POST on as a GET.
export fn redirect(location: String, status: Int = 303) HttpResponse!:
    var sent = headers()
    try sent.append("Location", location)
    return ok(HttpResponse(status: status, headers: sent, body: "".to_bytes()))

// Adapts a handler that maps a whole request to a whole response into an exchange handler for `serve`.
// The request body is read in full first.
export fn buffered(handler: fn(HttpRequest) HttpResponse) fn(var HttpExchange) Unit!:
    return fn(var exchange: HttpExchange): serve_buffered(handler, var exchange)

fn serve_buffered(
    handler: fn(HttpRequest) HttpResponse,
    var exchange: HttpExchange
) Unit!:
    let body = try read_body(var exchange)
    let request = HttpRequest(
        method: exchange.method(), path: exchange.path(), query: exchange.query(),
        headers: exchange.headers(), body: body, protocol: exchange.protocol()
    )
    return reply(var exchange, handler(request))

// Switches the exchange's connection to a WebSocket; the rules of `HttpExchange.upgrade` apply.
export fn upgrade(
    var exchange: HttpExchange, allowed_origins: List[String],
    subprotocols: List[String], max_message_bytes: Int?
) WebSocket!:
    let raw = try exchange.upgrade(allowed_origins, subprotocols, max_message_bytes)
    return ok(web_socket_from(raw))
