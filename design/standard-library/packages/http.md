+++
title = "HTTP clients and streaming hosts"
weight = 56
+++

# HTTP clients and streaming hosts

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

## `@std/http.ms`

## HttpClient operations

```text
fn send(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration) -> Result[ResponseBody, LibraryError]
fn send_stream(method: String, url: String, headers: Map[String, String], body: ReadStream, max_response_bytes: Int, timeout: Duration) -> Result[ResponseBody, LibraryError]
fn close() -> Unit
```

## ResponseBody operations

```text
fn status() -> Int
fn headers() -> Map[String, List[String]]
fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
fn close() -> Unit
```

## HttpExchange operations

```text
fn method() -> String
fn path() -> String
fn query() -> String
fn headers() -> Map[String, List[String]]
fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
fn send_headers(status: Int, headers: Map[String, List[String]]) -> Result[Unit, LibraryError]
fn write(data: Bytes) -> Result[Unit, IoError]
fn upgrade(allowed_origins: List[String], subprotocols: List[String], max_message_bytes: Int) -> Result[WebSocket, LibraryError]
fn close() -> Unit
```

The original [bounded buffered HTTP host](../hosts/http.md) and Network.request remain supported. The new reusable client and streaming host provide HTTP/1.1 and HTTP/2 without changing those existing record types. HTTP/3 is excluded by user instruction.

## Configuration

```text
type HttpClientOptions:
    max_redirects: Int
    max_idle_connections: Int
    max_header_bytes: Int
    idle_timeout: Duration
    decompress: Bool
    cookies: Bool
    tls: TlsOptions

type HttpServerOptions:
    max_requests: Int
    max_body_bytes: Int
    max_response_bytes: Int
    max_header_bytes: Int
    timeout: Duration
    grace: Duration
    tls: Optional[TlsOptions]
```

Client redirects/idle capacity/timeouts are nonnegative; header limit is positive and idle capacity is at most 65536. Server request capacity is 1–65536; header limit/timeout are positive; body/response limits and grace are nonnegative. None TLS serves plain HTTP/1.1; configured TLS serves HTTP/1.1 and HTTP/2 through native ALPN negotiation. Credentials/trust come from explicit TlsOptions. No ambient HTTP proxy is read.

HttpClient is a shared Closeable resource created through Network.http_client. It owns a pooled transport and optional public-suffix-aware cookie jar. Idle connections and lifetime are explicit options. Close stops admission, cancels in-flight requests, closes outstanding response bodies, joins their upload/read work and releases idle connections. Network close owns and joins clients too.

Send returns ResponseBody, not an implicitly buffered record. Read obeys the stream contract; cumulative decoded output is bounded by max_response_bytes. Status and duplicate headers remain available as metadata. Close before EOF cancels/discards the body; consumed bodies can reuse the pooled connection. Timeout covers DNS through body lifetime; parent cancellation unwinds. Gzip decoding is enabled only with decompress and remains subject to the expanded-byte bound. Invalid UTF-8 header values are rejected before constructing source Strings.

Send_stream borrows an explicitly shared ReadStream for the upload and does not close it. The response owns the upload work until response closure/completion: keep the input's scope open through the response scope. Under HTTP/1.1, streaming server responses enable full duplex so a response does not silently drain/close the outstanding upload. Upload faults retain source fault identity, not a generic transport success. Redirects requiring replay are returned to the caller for streaming bodies; immutable Bytes sends can follow configured redirects. A consumed prefix cannot be rolled back after failure.

Redirects honor max_redirects (zero returns the redirect response), reject TLS downgrade, recheck the Network policy on every destination, and remove explicit Authorization/Cookie/Proxy-Authorization when the origin changes. Automatic cookies are selected by the destination jar rather than copying source-origin headers. 4xx/5xx remain successful responses. Header names/values reject injection and callers cannot set host-managed framing fields.

## Streaming request host

Network.serve_stream accepts an ordinary handler and may be stored as a bound method. The handler signature is `fn(exchange: HttpExchange) -> Result[Unit, LibraryError]`. The server establishes a fixed request execution context, bounded admission, body/output/header limits, disconnect cancellation and timeout. The handler may read incrementally, emit headers once and write/flush bounded output, or upgrade to a WebSocket session. Source routes by ordinary method/path branching.

Read and write have separate synchronized gates. Send_headers accepts status 200–599 and ordered duplicate header values; it rejects repeated headers emission, CR/LF/NUL values, and caller-supplied framing. Write requires headers first, counts cumulative output bytes, applies native backpressure and disallows bodies for HEAD/204/304. Body bound failures return IoError.Failed with a limit diagnostic. Before headers, handler faults/domain errors produce a generic 500, or 504 for timeout where possible; after headers the host aborts transport rather than returning a misleading complete body. Returning success without headers produces 204.

HttpExchange belongs to its request: retained aliases report Closed once request cleanup ends. Server shutdown stops admission, waits grace, cancels remaining requests/sessions and joins them before returning. Hijacked WebSocket transports are explicitly included in request cleanup and joining. A server or Network cannot close from its own handler. Streaming source code needs no new function kind or detached task syntax.

## Network operations

```text
fn request(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration) -> Result[ClientResponse, LibraryError]
fn http_client(options: HttpClientOptions) -> Result[HttpClient, LibraryError]
fn serve_stream(address: String, handler: fn(exchange: HttpExchange) -> Result[Unit, LibraryError], options: HttpServerOptions) -> Result[HttpServer, LibraryError]
```
