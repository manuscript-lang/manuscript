+++
title = "http"
+++

# @std/http.ms

Import each required symbol with `import Name from "@std/http.ms"`.

## ClientResponse {data-api-kind="Record"}

Buffered response body with explicit common metadata access.

```manuscript
type ClientResponse:
    head: HttpResponseMetadata
    body: Bytes
    fn metadata() -> HttpResponseMetadata:
```

### ClientResponse.body

The complete response payload within the supplied byte bound.

```manuscript
body: Bytes
```

### ClientResponse.head

Current mutable metadata; replacing head detaches existing metadata aliases.

```manuscript
head: HttpResponseMetadata
```

### ClientResponse.metadata

Returns current head without copying; record clone is shallow.
Clone headers explicitly when separate mutable membership is needed.

```manuscript
fn metadata() -> HttpResponseMetadata:
```

## HttpClient {data-api-kind="Interface"}

Reusable HTTP client with connection pooling and explicit response limits.
Outbound headers retain separate values in their stored order.

```manuscript
interface HttpClient:
    fn close() -> Unit
    fn request(method: HttpMethod, url: String, headers: HttpHeaders, body: Bytes = "".to_bytes(), max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
    fn request_stream(method: HttpMethod, url: String, headers: HttpHeaders, body: ReadStream, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
```

### HttpClient.close

Cancels in-flight requests, closes open response bodies, and drops idle pooled connections.
Safe to call repeatedly; later requests return Closed.

```manuscript
fn close() -> Unit
```

### HttpClient.request

Sends immutable Bytes and returns a scoped streaming response body.

```manuscript
fn request(method: HttpMethod, url: String, headers: HttpHeaders, body: Bytes = "".to_bytes(), max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
```

### HttpClient.request_stream

Borrows ReadStream upload data through the scoped response lifetime.

```manuscript
fn request_stream(method: HttpMethod, url: String, headers: HttpHeaders, body: ReadStream, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
```

## HttpClientOptions {data-api-kind="Record"}

Connection, redirect, cookie, decompression, and TLS settings for an HTTP client.

```manuscript
type HttpClientOptions:
    max_redirects: Optional[Int] = none
    max_idle_connections: Optional[Int] = none
    max_header_bytes: Optional[Int] = none
    idle_timeout: Optional[Duration] = none
    decompress: Bool = false
    cookies: Bool = false
    tls: TlsOptions = TlsOptions(
        server_name: "",
        roots_pem: "",
        certificate_pem: "",
        private_key_pem: "",
        alpn: [],
        require_client_certificate: false
    )
```

### HttpClientOptions.cookies

When true, the client keeps an in-memory cookie jar for its lifetime, respecting public-suffix boundaries; when false (the default), no cookies are stored or sent automatically.

```manuscript
cookies: Bool = false
```

### HttpClientOptions.decompress

When true, gzip-encoded responses are decoded transparently, with `max_response_bytes` bounding the decoded size; when false (the default), bodies arrive exactly as sent.

```manuscript
decompress: Bool = false
```

### HttpClientOptions.idle_timeout

How long an idle pooled connection is kept before it is closed. none never expires it, and a negative duration is rejected.

```manuscript
idle_timeout: Optional[Duration] = none
```

### HttpClientOptions.max_header_bytes

Largest accepted size of a response header block, in bytes. Must be positive; none sets no cap.

```manuscript
max_header_bytes: Optional[Int] = none
```

### HttpClientOptions.max_idle_connections

Number of idle connections kept for reuse. Must be nonnegative; none sets no explicit cap.

```manuscript
max_idle_connections: Optional[Int] = none
```

### HttpClientOptions.max_redirects

Most redirects followed per request. 0 returns the redirect response itself, none sets no cap, and a negative count is rejected.
Redirects that downgrade from HTTPS, leave the network's restrictions, or carry user info are refused.

```manuscript
max_redirects: Optional[Int] = none
```

### HttpClientOptions.tls

TLS trust and client-certificate settings for `https` requests. The host name is taken from each URL, so `server_name` is ignored.

```manuscript
tls: TlsOptions = TlsOptions(
        server_name: "",
        roots_pem: "",
        certificate_pem: "",
        private_key_pem: "",
        alpn: [],
        require_client_certificate: false
    )
```

## HttpError {data-api-kind="Alternative"}

Errors returned for invalid requests, transport failures, timeouts, and limits.

```manuscript
type HttpError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case PermissionDenied
    case Closed
    case Timeout
    case Failed(message: String)
```

```manuscript
impl Error for HttpError:
    fn message() -> String:
```

### HttpError.Closed

The client or network was closed before or during the request.

```manuscript
case Closed
```

### HttpError.Failed

Transport, TLS, or protocol failure reported by the host, such as a refused connection or an exceeded redirect limit.

```manuscript
case Failed(message: String)
```

### HttpError.InvalidData

The response headers are not valid UTF-8, so they cannot become Strings.

```manuscript
case InvalidData
```

### HttpError.InvalidInput

The URL is not an `http` or `https` URL with a host, valid port, and no user info; a method, header name, or value is malformed or host-managed; or a limit or timeout is negative.

```manuscript
case InvalidInput
```

### HttpError.LimitExceeded

A buffered response body is larger than `max_response_bytes`.

```manuscript
case LimitExceeded
```

### HttpError.PermissionDenied

The network's restrictions disallow the host, a resolved address, or a redirect destination.

```manuscript
case PermissionDenied
```

### HttpError.Timeout

The request timeout elapsed before the response completed.

```manuscript
case Timeout
```

### HttpError.Failed.message

Host-provided failure text; `message()` returns it verbatim, so it can name addresses.

```manuscript
message: String
```

### HttpError.Error.message

Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `HTTP: <reason>`.

```manuscript
fn message() -> String:
```

## HttpExchange {data-api-kind="Interface"}

One streaming server exchange. Read or write incrementally and close when done.
Received headers are one shared mutable object; repeated values stay separate.

```manuscript
interface HttpExchange:
    fn close() -> Unit
    fn headers() -> HttpHeaders
    fn method() -> HttpMethod
    fn path() -> String
    fn query() -> String
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    fn send_headers(status: Int, headers: HttpHeaders) -> Result[Unit, HttpError]
    fn upgrade(allowed_origins: List[String], subprotocols: List[String], max_message_bytes: Optional[Int] = none) -> Result[WebSocket, WebSocketError]
    fn write(data: Bytes) -> Result[Unit, IoError]
```

### HttpExchange.close

Ends the exchange, interrupting reads or writes in progress.
Later operations return Closed.

```manuscript
fn close() -> Unit
```

### HttpExchange.headers

Returns the request headers as shared mutable fields with every repeated value retained.

```manuscript
fn headers() -> HttpHeaders
```

### HttpExchange.method

Returns the request method, using the Custom case for extension tokens.

```manuscript
fn method() -> HttpMethod
```

### HttpExchange.path

Returns the percent-decoded request path with dot segments resolved.
Requests with an encoded slash or NUL are rejected before the handler runs.

```manuscript
fn path() -> String
```

### HttpExchange.query

Returns the raw query string without the leading `?`; it is empty when there is none.

```manuscript
fn query() -> String
```

### HttpExchange.read

Returns the next chunk of the request body, at most `max_bytes` and never more than 65536, or none at the end of the body.
Reading past `max_body_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.

```manuscript
fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
```

### HttpExchange.send_headers

Sends the status line and headers once, before any body is written.
The status must be 200 through 599, header names cannot be `Content-Length`, `Transfer-Encoding`, or `Connection`, and header bytes are bounded by `max_header_bytes`. A second call returns InvalidInput and a closed exchange returns Closed.

```manuscript
fn send_headers(status: Int, headers: HttpHeaders) -> Result[Unit, HttpError]
```

### HttpExchange.upgrade

Switches the connection to a WebSocket after checking the `Origin` header. Requests without an Origin are accepted; otherwise it must exactly match an entry of `allowed_origins`, or, when that list is empty, match the request's own scheme and host.
`subprotocols` lists the protocols the server accepts, and `max_message_bytes` must be positive when given. An exchange that already sent headers or upgraded returns InvalidInput, and a request that is not a valid WebSocket upgrade returns Failed.

```manuscript
fn upgrade(allowed_origins: List[String], subprotocols: List[String], max_message_bytes: Optional[Int] = none) -> Result[WebSocket, WebSocketError]
```

### HttpExchange.write

Writes one chunk of the response body and flushes it.
`send_headers` must come first, and writing beyond `max_response_bytes` returns IoError.Failed. Responses to HEAD requests and with status 204 or 304 cannot have a body.

```manuscript
fn write(data: Bytes) -> Result[Unit, IoError]
```

## HttpHeaders {data-api-kind="Native type"}

Mutable HTTP fields with ASCII case-insensitive names and separate byte values.
Names keep first-insertion order and spelling; values keep append order.
Lookup shares list membership. Use clone() to separate mutable membership.

```manuscript
type HttpHeaders:
    fn append(name: String, value: Bytes) -> Result[Unit, HttpError]:
    fn values(name: String) -> Optional[List[Bytes]]:
    fn text(name: String) -> Result[Optional[List[String]], HttpError]:
    fn names() -> List[String]:
    fn remove(name: String) -> Bool:
    fn clone() -> HttpHeaders:
```

### HttpHeaders.append

Appends raw bytes under a valid HTTP name; invalid names return InvalidInput.
Transport operations additionally validate UTF-8, framing and field values.

```manuscript
fn append(name: String, value: Bytes) -> Result[Unit, HttpError]:
```

### HttpHeaders.clone

Copies name/list membership and shares immutable Bytes values.

```manuscript
fn clone() -> HttpHeaders:
```

### HttpHeaders.names

Returns first-inserted spellings in insertion order.

```manuscript
fn names() -> List[String]:
```

### HttpHeaders.remove

Removes a name; existing list aliases are detached from this header object.

```manuscript
fn remove(name: String) -> Bool:
```

### HttpHeaders.text

Decodes every value; invalid UTF-8 returns InvalidData without partial success.

```manuscript
fn text(name: String) -> Result[Optional[List[String]], HttpError]:
```

### HttpHeaders.values

Returns shared mutable membership, or none for an absent name.

```manuscript
fn values(name: String) -> Optional[List[Bytes]]:
```

## HttpMethod {data-api-kind="Alternative"}

Known HTTP methods, plus extension tokens validated by outgoing operations.

```manuscript
type HttpMethod:
    case Get
    case Head
    case Post
    case Put
    case Patch
    case Delete
    case Connect
    case Options
    case Trace
    case Custom(value: String)
    fn text() -> String:
```

### HttpMethod.Connect

Establishes a tunnel to the request target.

```manuscript
case Connect
```

### HttpMethod.Custom

Carries an extension token; requests reject empty or malformed tokens.

```manuscript
case Custom(value: String)
```

### HttpMethod.Delete

Removes the selected representation.

```manuscript
case Delete
```

### HttpMethod.Get

Requests the selected representation.

```manuscript
case Get
```

### HttpMethod.Head

Requests response metadata without a body.

```manuscript
case Head
```

### HttpMethod.Options

Asks which communication options the target supports, without transferring a body.

```manuscript
case Options
```

### HttpMethod.Patch

Applies a partial modification.

```manuscript
case Patch
```

### HttpMethod.Post

Submits a representation for processing.

```manuscript
case Post
```

### HttpMethod.Put

Replaces the selected representation.

```manuscript
case Put
```

### HttpMethod.Trace

Requests a diagnostic loopback.

```manuscript
case Trace
```

### HttpMethod.Custom.value

The method token; it must be a non-empty HTTP token such as PURGE.

```manuscript
value: String
```

### HttpMethod.text

Returns the method token; outgoing requests reject malformed Custom tokens.

```manuscript
fn text() -> String:
```

## HttpRequest {data-api-kind="Record"}

Buffered request accepted by the simple HTTP server handler.

```manuscript
type HttpRequest:
    method: HttpMethod
    path: String
    query: String
    headers: HttpHeaders
    body: Bytes
```

### HttpRequest.body

The complete request body, at most `max_body_bytes` long.

```manuscript
body: Bytes
```

### HttpRequest.headers

The request headers as mutable fields with every repeated value retained.

```manuscript
headers: HttpHeaders
```

### HttpRequest.method

The request method, using the Custom case for extension tokens.

```manuscript
method: HttpMethod
```

### HttpRequest.path

The percent-decoded request path with dot segments resolved, so `/a/../b` arrives as `/b`.

```manuscript
path: String
```

### HttpRequest.query

The raw query string without the leading `?`; empty when there is none.

```manuscript
query: String
```

## HttpResponse {data-api-kind="Record"}

Buffered response returned by the simple HTTP server handler.

```manuscript
type HttpResponse:
    status: Int
    headers: HttpHeaders
    body: Bytes
```

### HttpResponse.body

The response body bytes, which must not exceed `max_response_bytes`; the server sets the content length.

```manuscript
body: Bytes
```

### HttpResponse.headers

The response headers to send; `Content-Length`, `Transfer-Encoding`, and `Connection` are rejected with a 500 error.

```manuscript
headers: HttpHeaders
```

### HttpResponse.status

The HTTP status code, which must be 200 through 599; other values are answered with a 500 error.

```manuscript
status: Int
```

## HttpResponseMetadata {data-api-kind="Record"}

Response status and headers shared by buffered and streaming response access.

```manuscript
type HttpResponseMetadata:
    status: Int
    headers: HttpHeaders
```

### HttpResponseMetadata.headers

The shared mutable fields, with every repeated value retained.

```manuscript
headers: HttpHeaders
```

### HttpResponseMetadata.status

The received status; editing metadata leaves wire/body behavior unchanged.

```manuscript
status: Int
```

## HttpServer {data-api-kind="Interface"}

A running HTTP server. Close it to stop accepting new requests.

```manuscript
interface HttpServer:
    fn address() -> String
    fn close() -> Unit
    fn wait() -> Result[Unit, IoError]
```

### HttpServer.address

Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.

```manuscript
fn address() -> String
```

### HttpServer.close

Stops accepting connections, waits up to the grace period for in-flight requests, then cancels the rest and waits for them.
Safe to call repeatedly. A request handler calling close on its own server faults, and a shutdown error is raised as a fault.

```manuscript
fn close() -> Unit
```

### HttpServer.wait

Blocks until the server stops. Returns Ok after a normal `close`, or IoError.Failed with the host's text if serving ended with an error.
Cancelling the waiting task stops the wait.

```manuscript
fn wait() -> Result[Unit, IoError]
```

## HttpServerOptions {data-api-kind="Record"}

Request and response limits, deadlines, graceful shutdown, and TLS server settings.

```manuscript
type HttpServerOptions:
    max_requests: Optional[Int] = none
    max_body_bytes: Optional[Int] = none
    max_response_bytes: Optional[Int] = none
    max_header_bytes: Optional[Int] = none
    timeout: Optional[Duration] = none
    grace: Optional[Duration] = none
    tls: Optional[TlsOptions] = none
```

### HttpServerOptions.grace

How long `close` waits for in-flight requests to finish before cancelling them. none waits without limit and 0 cancels immediately.

```manuscript
grace: Optional[Duration] = none
```

### HttpServerOptions.max_body_bytes

Largest accepted request body, in bytes. Must be nonnegative; none sets no cap.

```manuscript
max_body_bytes: Optional[Int] = none
```

### HttpServerOptions.max_header_bytes

Largest accepted request header block and largest response header block, in bytes. Must be positive; none sets no cap.

```manuscript
max_header_bytes: Optional[Int] = none
```

### HttpServerOptions.max_requests

Most requests handled at once; further requests are answered with 503. Must be positive; none sets no cap.

```manuscript
max_requests: Optional[Int] = none
```

### HttpServerOptions.max_response_bytes

Most response body bytes a handler may write, in bytes. Must be nonnegative; none sets no cap.

```manuscript
max_response_bytes: Optional[Int] = none
```

### HttpServerOptions.timeout

Per-request time budget covering reading the request, running the handler, and writing the response. none sets no deadline.

```manuscript
timeout: Optional[Duration] = none
```

### HttpServerOptions.tls

Some(options) serves HTTPS and negotiates HTTP/2 or HTTP/1.1 through ALPN; none, the default, serves plain HTTP/1.1.

```manuscript
tls: Optional[TlsOptions] = none
```

## ResponseBody {data-api-kind="Interface"}

Streaming response body returned by reusable HTTP client operations.
Metadata remains available after close and shares one mutable header object.

```manuscript
interface ResponseBody:
    fn close() -> Unit
    fn metadata() -> HttpResponseMetadata
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
```

### ResponseBody.close

Cancels the rest of the response and releases its connection.
Safe to call repeatedly; reads afterwards return Closed. A fully read body lets the connection be reused.

```manuscript
fn close() -> Unit
```

### ResponseBody.metadata

Returns the response head (status and headers) without copying; it stays available after close.

```manuscript
fn metadata() -> HttpResponseMetadata
```

### ResponseBody.read

Returns the next chunk of the response body, at most `max_bytes` and never more than 65536, or none at the end of the body.
Reading past the request's `max_response_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.

```manuscript
fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
```

## headers {data-api-kind="Function"}

Creates empty mutable headers. No header values are joined or comma-combined.

```manuscript
fn headers() -> HttpHeaders:
```

