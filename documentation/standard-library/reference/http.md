+++
title = "http"
+++

# @std/http.ms

Import each required symbol with `import Name from "@std/http.ms"`.

## ClientResponse {data-api-kind="Record"}

Buffered HTTP response metadata and body. Header names have canonical spelling;
Map lookup is case-sensitive. Lists preserve separate values in received order.

```manuscript
type ClientResponse:
    status: Int
    headers: Map[String, List[String]]
    body: Bytes
```

### ClientResponse.body

The complete response body bytes, never longer than the request's `max_response_bytes`.

```manuscript
body: Bytes
```

### ClientResponse.headers

Response headers keyed by canonical name, such as `Content-Type`, in sorted name order. Repeated headers keep every value in received order.

```manuscript
headers: Map[String, List[String]]
```

### ClientResponse.status

The numeric HTTP status code. 4xx and 5xx statuses are ordinary responses, not errors.

```manuscript
status: Int
```

## HttpClient {data-api-kind="Interface"}

Reusable HTTP client with connection pooling and explicit response limits.
Outbound case-equivalent header keys append values in Map insertion order.

```manuscript
interface HttpClient:
    fn close() -> Unit
    fn send(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
    fn send_stream(method: String, url: String, headers: Map[String, String], body: ReadStream, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
```

### HttpClient.close

Cancels in-flight requests, closes open response bodies, and drops idle pooled connections.
Safe to call repeatedly; later requests return Closed.

```manuscript
fn close() -> Unit
```

### HttpClient.send

Sends a request with a buffered body and returns once the response headers arrive; read the body from the returned ResponseBody.
Redirects follow the client's `max_redirects`, and `timeout` covers DNS through the end of the body. Cumulative body bytes above `max_response_bytes` fail the read.

```manuscript
fn send(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
```

### HttpClient.send_stream

Sends a request whose body is pulled from `body` in chunks and returns once the response headers arrive.
Redirects are never followed, because a consumed stream cannot be replayed. The other limits behave as for `send`.

```manuscript
fn send_stream(method: String, url: String, headers: Map[String, String], body: ReadStream, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
```

## HttpClientOptions {data-api-kind="Record"}

Connection, redirect, cookie, decompression, and TLS settings for an HTTP client.

```manuscript
type HttpClientOptions:
    max_redirects: Optional[Int] = none
    max_idle_connections: Optional[Int] = none
    max_header_bytes: Optional[Int] = none
    idle_timeout: Optional[Duration] = none
    decompress: Bool
    cookies: Bool
    tls: TlsOptions
```

### HttpClientOptions.cookies

When true, the client keeps an in-memory cookie jar for its lifetime, respecting public-suffix boundaries; when false, no cookies are stored or sent automatically.

```manuscript
cookies: Bool
```

### HttpClientOptions.decompress

When true, gzip-encoded responses are decoded transparently, with `max_response_bytes` bounding the decoded size; when false, bodies arrive exactly as sent.

```manuscript
decompress: Bool
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
tls: TlsOptions
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
Received header names have canonical spelling; Map lookup is case-sensitive.
Sending case-equivalent names appends each list in Map insertion order.

```manuscript
interface HttpExchange:
    fn close() -> Unit
    fn headers() -> Map[String, List[String]]
    fn method() -> String
    fn path() -> String
    fn query() -> String
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    fn send_headers(status: Int, headers: Map[String, List[String]]) -> Result[Unit, HttpError]
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

Returns the request headers keyed by canonical name in sorted name order; repeated headers keep every value in received order.

```manuscript
fn headers() -> Map[String, List[String]]
```

### HttpExchange.method

Returns the request method exactly as sent, such as `GET`.

```manuscript
fn method() -> String
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
fn send_headers(status: Int, headers: Map[String, List[String]]) -> Result[Unit, HttpError]
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

## HttpRequest {data-api-kind="Record"}

Buffered request accepted by the simple HTTP server handler.

```manuscript
type HttpRequest:
    method: String
    path: String
    query: String
    headers: Map[String, Bytes]
    body: Bytes
    fn header(name: String) -> Optional[Bytes]:
```

### HttpRequest.body

The complete request body, at most `max_body_bytes` long.

```manuscript
body: Bytes
```

### HttpRequest.headers

Request headers keyed by canonical name, such as `Content-Type`, in sorted name order. Repeated values are joined with newlines in received order.

```manuscript
headers: Map[String, Bytes]
```

### HttpRequest.method

The request method exactly as sent, such as `GET`.

```manuscript
method: String
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

### HttpRequest.header

Finds a header using ASCII case-insensitive names, or returns `none`.
Leaves Map keys unchanged. Repeated received values remain newline-joined bytes.
If a manually built Map has equivalent names, returns its first matching entry.

```manuscript
fn header(name: String) -> Optional[Bytes]:
```

## HttpResponse {data-api-kind="Record"}

Buffered response returned by the simple HTTP server handler.
Case-equivalent header keys emit separate values in Map insertion order.
Use HttpExchange.send_headers for repeated values under one exact Map key.

```manuscript
type HttpResponse:
    status: Int
    headers: Map[String, String]
    body: Bytes
```

### HttpResponse.body

The response body bytes, which must not exceed `max_response_bytes`; the server sets the content length.

```manuscript
body: Bytes
```

### HttpResponse.headers

Response headers to send. Names that differ only in case are all sent, in map order; `Content-Length`, `Transfer-Encoding`, and `Connection` are rejected with a 500 error.

```manuscript
headers: Map[String, String]
```

### HttpResponse.status

The HTTP status code, which must be 200 through 599; other values are answered with a 500 error.

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
    tls: Optional[TlsOptions]
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

Required: some(options) serves HTTPS and negotiates HTTP/2 or HTTP/1.1 through ALPN, while none serves plain HTTP/1.1.

```manuscript
tls: Optional[TlsOptions]
```

## ResponseBody {data-api-kind="Interface"}

Streaming response body returned by HTTP client operations. Header names have
canonical spelling; Map lookup is case-sensitive. Lists keep received order.

```manuscript
interface ResponseBody:
    fn close() -> Unit
    fn headers() -> Map[String, List[String]]
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    fn status() -> Int
```

### ResponseBody.close

Cancels the rest of the response and releases its connection.
Safe to call repeatedly; reads afterwards return Closed. A fully read body lets the connection be reused.

```manuscript
fn close() -> Unit
```

### ResponseBody.headers

Returns the response headers keyed by canonical name in sorted name order; repeated headers keep every value in received order.

```manuscript
fn headers() -> Map[String, List[String]]
```

### ResponseBody.read

Returns the next chunk of the response body, at most `max_bytes` and never more than 65536, or none at the end of the body.
Reading past the request's `max_response_bytes` returns IoError.Failed, and a non-positive `max_bytes` returns InvalidInput.

```manuscript
fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
```

### ResponseBody.status

Returns the numeric HTTP status code, available as soon as headers arrive.

```manuscript
fn status() -> Int
```

## header_values {data-api-kind="Function"}

Finds all values under ASCII case-equivalent names without changing Map keys.
Returns none if absent, or some(empty) for a present empty list. Copies list
membership and preserves Map insertion order followed by each list's order.

```manuscript
fn header_values(headers: Map[String, List[String]], name: String) -> Optional[List[String]]:
```

