# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Connection from "@std/net.ms"
import DatagramSocket from "@std/net.ms"
import DnsRecord from "@std/net.ms"
import Duration from "@std/time.ms"
import IoError from "@std/io.ms"
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
    get metadata -> HttpResponseMetadata:

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
    get text -> String:

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
    get headers -> HttpHeaders
    # Returns the request method, using the Custom case for extension tokens.
    get method -> HttpMethod
    # Returns the percent-decoded request path with dot segments resolved.
    # Requests with an encoded slash or NUL are rejected before the handler runs.
    get path -> String
    # Returns the raw query string without the leading `?`; it is empty when there is none.
    get query -> String
    # Returns the next chunk of the request body, at most `max_bytes` and never more than 65536, or none at the end of the body.
    # Reading past `max_body_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    # Sends the status line and headers once, before any body is written.
    # The status must be 200 through 599, header names cannot be `Content-Length`, `Transfer-Encoding`, or `Connection`, and header bytes are bounded by `max_header_bytes`. A second call returns InvalidInput and a closed exchange returns Closed.
    fn send_headers(status: Int, headers: HttpHeaders) -> Result[Unit, HttpError]
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
    get address -> String
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
    get metadata -> HttpResponseMetadata
    # Returns the next chunk of the response body, at most `max_bytes` and never more than 65536, or none at the end of the body.
    # Reading past the request's `max_response_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]

impl Error for HttpError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `HTTP: <reason>`.
    fn message() -> String:

# documentation documentation/standard-library/http.md
# +++
# title = "HTTP"
# weight = 16
# +++
#
# # HTTP
#
# API reference: [HTTP](reference/http.md), [Network](reference/net.md), and [Server-Sent Events](reference/sse.md).
#
# Use HttpClient for reusable outbound requests and HttpExchange for streaming request handling. Response bodies are resources: read them in chunks and close them. A received HTTP error status is still a response you can inspect.
#
# ## Protocols
#
# `Network.serve` invokes a handler with a buffered `HttpRequest` and emits its `HttpResponse`. `Network.request` buffers the response into `ClientResponse`. `HttpClient.request` and `request_stream` return a scoped `ResponseBody`; its status and headers use the same `metadata` record as buffered responses, and its body is read incrementally. Streaming servers receive `HttpExchange`. TLS-enabled reusable clients and streaming servers support HTTP/1.1 and HTTP/2.
#
# ## Configuration
#
# Limits and deadlines are optional. Supplied redirect counts, idle capacity, byte budgets, deadlines, and grace must be nonnegative; supplied header and request-admission caps must be positive. `HttpServerOptions()` and `HttpClientOptions()` are valid: server `tls` defaults to `none` (plain HTTP/1.1), and a client defaults to `decompress: false`, `cookies: false` and an empty `TlsOptions`, which verifies servers against system trust. With TLS configured, native ALPN negotiation selects HTTP/1.1 or HTTP/2. Credentials, custom trust roots and server certificates always come from explicit TlsOptions; there is no insecure option. `Network.request` and `HttpClient.request` default `body` to empty Bytes; `headers` stays required because `HttpHeaders` is an opaque native value, so a plain GET passes `headers()`. No ambient HTTP proxy is read.
#
# ### Client lifetime
#
# Create a shared HttpClient through `Network.http_client`. It implements Closeable, so keep it in a `with` scope. It owns a pooled transport and optional public-suffix-aware cookie jar. Idle connections and lifetime are explicit options. Close stops admission, cancels in-flight requests, closes outstanding response bodies, joins their upload/read work and releases idle connections. Network close owns and joins clients too.
#
# ### Reading a response
#
# `HttpClient.request` returns a ResponseBody that you read incrementally. Reads follow the stream contract. `max_response_bytes` limits the cumulative decoded output. Status and duplicate headers remain available as metadata. Close before EOF cancels/discards the body; consumed bodies can reuse the pooled connection. Timeout covers DNS through body lifetime; parent cancellation unwinds. Gzip decoding is enabled only with decompress and remains subject to the expanded-byte bound. Invalid UTF-8 header values are rejected before constructing source Strings.
#
# ### Streaming an upload
#
# `request_stream` borrows an explicitly shared ReadStream for the upload and does not close it. The response owns the upload work until response closure/completion: keep the input's scope open through the response scope. Under HTTP/1.1, streaming server responses enable full duplex so a response does not silently drain/close the outstanding upload. Upload faults retain source fault identity, not a generic transport success. Redirects requiring replay are returned to the caller for streaming bodies; immutable Bytes sends can follow configured redirects. A consumed prefix cannot be rolled back after failure.
#
# ### Redirects and HTTP status
#
# Redirects honor max_redirects (zero returns the redirect response), reject TLS downgrade, recheck the Network policy on every destination, and remove explicit Authorization/Cookie/Proxy-Authorization when the origin changes. Automatic cookies are selected by the destination jar rather than copying source-origin headers. HTTP 4xx and 5xx statuses are returned responses, rather than transport errors. Header names/values reject injection and callers cannot set host-managed framing fields.
#
# ## Request API
#
# `Network` and `network()` are exported by `@std/net.ms`. Buffered request/response records, streaming exchanges, and server types live in `@std/http.ms`.
#
# `Network.serve` accepts `fn(request: HttpRequest) -> HttpResponse` and returns a scoped HttpServer. Request headers are bytes, the raw query stays encoded, and source code routes by ordinary method/path branching. Both server forms validate the original decoded path's UTF-8 before normalization, reject encoded slash (`%2F`, either case) or NUL with 400, then resolve dot segments (including `%2e%2e`) and repeated slashes while preserving a trailing slash. Decoding happens once: `/a%252Fb` reaches the handler as `/a%2Fb`, and handlers must not decode it again. Query escapes stay unchanged. These URL rules do not make filesystem joins a sandbox. Request headers, buffered and streaming, include `Host` when the client sent one. Responses require status 200–599, valid header names and values, and a body within any supplied response budget. See [the Network reference](reference/net.md#network) for its exact optional admission, byte, deadline, and grace parameters.
#
# Client disconnection cancels the request and nested task-group work. Started work joins and registered cleanup runs before the request ends. Handler faults become 500 responses and reach diagnostics; deadline expiry produces 504 where the transport permits it. Oversized buffered request bodies receive 413, and excess admission under a supplied cap receives 503 without invoking a handler.
#
# Schedulers used by handlers retain their construction lifetime. Accepted work uses that scheduler's context rather than the submitting request's deadline or disconnect signal. Construct shared schedulers outside request scopes, keep their dependencies open, and acquire operation resources inside each callback. Close them before releasing application resources.
#
# ## Header lookup and repeated values
#
# Use `HttpHeaders` everywhere HTTP fields cross an API: buffered request/response records, client inputs, response metadata, exchange reads/writes and WebSocket handshake inputs. `headers()` creates an empty mutable object. `append(name, value)` appends immutable Bytes under an ASCII case-insensitive name; it rejects malformed names with `HttpError.InvalidInput`. Names keep their first spelling and insertion position, while values keep append order. Appending `x-dup: first` and `X-Dup: second` retains both values under one name. Separate `Set-Cookie` fields remain separate, including cookies with commas in `Expires`.
#
# `values(name)` returns `Optional[List[Bytes]]`. An absent name returns `none`; a present name with no values returns `some` empty list. The list is shared membership: repeated lookups return the same list, appends are visible through existing aliases, and list edits affect subsequent sends. `remove(name)` detaches that name; old list aliases remain usable but no longer affect the header object. Reinserting a removed name gives it a new position/list. `clone()` explicitly copies the names and list membership while sharing immutable Bytes. `names()` returns an ordered list of spellings. These are mutable data, subject to ordinary explicit synchronization when shared between tasks.
#
# Transport adapters convert received host headers once. Header and metadata reads do not copy membership. Buffered `ClientResponse.metadata` returns the current `response.head`: reads share that mutable record while head is unchanged. Replacing `response.head` detaches old aliases, which remain usable but no longer describe the current head. `ResponseBody.metadata` returns its stored mutable record, including after close. Status/headers edits are alias-visible and do not alter the received wire response.
#
# Record clone is shallow. `response.clone()` copies the buffered response record fields while sharing head; `response.head.clone()` copies metadata fields while sharing headers. To separate mutable header membership, explicitly clone headers and assign that object to the copied metadata. No record or header membership is copied merely by reading metadata.
#
# Host header names are sorted before conversion for stable received name order, including direct host maps with case-colliding keys; each exact host entry contributes all of its values. Values retain wire order within each name. Native HTTP serialization may sort different names, so there is no global wire order guarantee between names.
#
# `text(name)` explicitly returns `Result[Optional[List[String]], HttpError]`: valid bytes are decoded without joining or comma-combining; invalid UTF-8 in any value returns `InvalidData`, with no partial result. It allocates decoded text membership because conversion was requested. Buffered server input retains raw non-UTF-8 bytes. Streaming server input still rejects non-UTF-8 headers with 400, and clients still return `HttpError.InvalidData` for non-UTF-8 response metadata. Choosing one byte-valued representation does not broaden these transport policies.
#
# Outgoing names must be ASCII HTTP tokens; HTTP request/response values must be valid UTF-8 without control bytes except tab. CR, LF, NUL, and DEL are invalid. Every send validates current values, including edits through a shared list, before emitting caller fields. Invalid buffered responses become 500; invalid client headers or `send_headers` return `HttpError.InvalidInput`. Clients reject `Host`, `Content-Length`, and `Transfer-Encoding`; servers reject `Content-Length`, `Transfer-Encoding`, and `Connection` regardless of casing. WebSocket handshake restrictions and explicit security settings remain in force.
#
# ### Migration from text maps
#
# Encode each old String value as Bytes and call `append` in the original insertion order. For old list-valued maps, append every list item separately; never select only the first/last value or join cookies. Replace buffered `request.header(name)` and list-map `header_values` with `request.headers.values(name)` or explicit `text(name)`. Buffered headers are no longer newline-joined. A proxy can pass the same header type after removing host-managed framing and hop-by-hop fields; use `clone()` when those edits should be local.
#
# Use `response.metadata.status` and `response.metadata.headers` for buffered and streaming response consumption. Buffered ClientResponse construction uses `head: HttpResponseMetadata` and `body: Bytes`; fake constructors build head once. Outgoing HttpResponse retains its status/headers/body construction fields. Reusable client `send`/`send_stream` calls become `request`/`request_stream`; their results remain streaming `ResponseBody`, and streaming uploads still borrow ReadStream. `Network.request` continues to buffer ClientResponse. This rename does not consume or materialize a streaming body. Buffered `serve(limit:)` becomes `serve(max_requests:)`, matching HttpServerOptions without changing omitted/zero/negative handling.
#
# Method parameters and incoming request methods use `HttpMethod.Get`, `Head`, `Post`, `Put`, `Patch`, `Delete`, `Connect`, `Options`, `Trace`, or `Custom(value)`. `text` returns the token, and outgoing requests reject empty/malformed Custom tokens as `HttpError.InvalidInput`. Case-sensitive extension tokens remain available. WebSocket and TLS option naming is unchanged.
#
# ## Server-Sent Events
#
# `@std/sse.ms` decodes the `text/event-stream` wire format, so you do not write the chunk and line state machine yourself. Chunks may split any line, CRLF pair or UTF-8 scalar; the decoder reassembles them.
#
# For a push decoder, create one with `decoder`, pass each chunk to `feed`, which returns the events it completed, and call `finish` at end of input.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import {decoder, feed, finish} from "@std/sse.ms"
# import panic from "@std/faults.ms"
#
# test "events split across chunks":
#     let created = decoder().unwrap()
#     let first = feed(decoder: created, chunk: "event: tick\r\ndata: 1\r".to_bytes()).unwrap()
#     let second = feed(decoder: created, chunk: "\n\r\n".to_bytes()).unwrap()
#
#     if first.length != 0 or second.length != 1: return panic("one event expected")
#     if second.at(0).unwrap().event != "tick": return panic("event type")
#
#     finish(created).unwrap()
# ```
#
# To pull events from a stream, wrap any `ReadStream` with `reader` and call `next_event` until it returns `none`. `borrow_body` views a `ResponseBody` as a `ReadStream`. This fragment assumes a `client` from the sections above:
#
# ```text
# with response = try client.request(
#     method: HttpMethod.Get,
#     url: url,
#     headers: headers()
# ):
#     let events = try reader(input: borrow_body(response))
#     while true:
#         let event = try next_event(events)
#         if event.is_none: break
#         use(event.unwrap())
# ```
#
# The decoder follows the HTML Server-Sent Events rules. LF, CR and CRLF end lines. A leading byte order mark is removed once. Lines starting with `:` are ignored. After the first colon, one leading space is removed from the value. Repeated `data` lines are joined with LF. `event` sets the type, which defaults to `message` and applies to one event. `id` persists across events and is ignored when it contains NUL. `retry` accepts only ASCII digits and is exposed as `decoder.retry`. An event with no `data` line is not dispatched.
#
# Errors keep their domain identity: `InvalidData` for a line that is not UTF-8, `LimitExceeded` when a line exceeds `SseLimits.max_line_bytes` or an event exceeds `max_event_bytes` (comments do not count), `Truncated` when the stream ends inside a line or before the blank line that completes an event, and `ReadFailed` carrying the original `IoError`. A truncated event is reported rather than dispatched, and an error is final for that decoder.
#
# The reader borrows its stream and never closes it. Cancel a blocked read the way you would for the stream itself, by closing the response or cancelling the surrounding scope; the read then fails and surfaces as `ReadFailed`.
#
# ## Error boundaries
#
# `request`, `http_client`, `request_stream`, `serve_stream`, and `send_headers` use `HttpError`. Buffered `serve` and `HttpServer.wait` use `IoError`. Streaming body reads and exchange reads/writes also use `IoError`, while upgrades use `WebSocketError`. These retain their domain error types; use an explicit match or a compatible `Error` boundary when composing operations. Both buffered and streaming admission use `max_requests`.
#
# ## Streaming request servers
#
# Network.serve_stream accepts an ordinary handler and may be stored as a bound method. The handler signature is `fn(exchange: HttpExchange) -> Result[Unit, HttpError]`. The server establishes a fixed request execution context, optional admission and body/output/header budgets, disconnect cancellation, and an optional timeout. The handler may read incrementally, emit headers once and write/flush bounded output, or upgrade to a WebSocket session. Source routes by ordinary method/path branching.
#
# ### Response ordering and limits
#
# Read and write have separate synchronized gates. Send_headers accepts status 200–599 and ordered duplicate header values; it rejects repeated headers emission, CR/LF/NUL values, and caller-supplied framing. Write requires headers first, counts cumulative output bytes, applies native backpressure and disallows bodies for HEAD/204/304. Body bound failures return IoError.Failed with a limit diagnostic. Before headers, handler faults/domain errors produce a generic 500, or 504 for timeout where possible; after headers the host aborts transport rather than returning a misleading complete body. Returning success without headers produces 204.
#
# ### Request and server lifetime
#
# HttpExchange belongs to its request: retained aliases report Closed once request cleanup ends. Server shutdown stops admission, waits grace, cancels remaining requests/sessions and joins them before returning. Hijacked WebSocket transports are explicitly included in request cleanup and joining. A server or Network cannot close from its own handler. Streaming source code needs no new function kind or detached task syntax.
# end-documentation
