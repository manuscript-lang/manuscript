+++
title = "HTTP clients and streaming hosts"
weight = 56
+++

# HTTP clients and streaming hosts

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Use HttpClient for reusable outbound requests and HttpExchange for streaming request handling. Response bodies are resources: read them in chunks and close them. A received HTTP error status is still a response you can inspect.

## `@std/http.ms`

## HttpClient operations

```text
fn send(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration) -> Result[ResponseBody&Shareable, HttpError]
fn send_stream(method: String, url: String, headers: Map[String, String], body: ReadStream&Shareable, max_response_bytes: Int, timeout: Duration) -> Result[ResponseBody&Shareable, HttpError]
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
fn send_headers(status: Int, headers: Map[String, List[String]]) -> Result[Unit, HttpError]
fn write(data: Bytes) -> Result[Unit, IoError]
fn upgrade(allowed_origins: List[String], subprotocols: List[String], max_message_bytes: Int) -> Result[WebSocket&Shareable, WebSocketError]
fn close() -> Unit
```

## Compatibility

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

### Option limits

Client redirect counts, idle capacity, and timeouts must be nonnegative. The header limit must be positive, and idle capacity cannot exceed 65536. Server request capacity is 1–65536. Header limits and timeout must be positive. Body and response limits and grace must be nonnegative. With no TLS configuration, the server uses plain HTTP/1.1. With TLS configured, native ALPN negotiation selects HTTP/1.1 or HTTP/2. Credentials/trust come from explicit TlsOptions. No ambient HTTP proxy is read.

### Client lifetime

Create a shared HttpClient through `Network.http_client`. It implements Closeable, so keep it in a `with` scope. It owns a pooled transport and optional public-suffix-aware cookie jar. Idle connections and lifetime are explicit options. Close stops admission, cancels in-flight requests, closes outstanding response bodies, joins their upload/read work and releases idle connections. Network close owns and joins clients too.

### Reading a response

`send` returns a ResponseBody that you read incrementally. Reads follow the stream contract. `max_response_bytes` limits the cumulative decoded output. Status and duplicate headers remain available as metadata. Close before EOF cancels/discards the body; consumed bodies can reuse the pooled connection. Timeout covers DNS through body lifetime; parent cancellation unwinds. Gzip decoding is enabled only with decompress and remains subject to the expanded-byte bound. Invalid UTF-8 header values are rejected before constructing source Strings.

### Streaming an upload

Send_stream borrows an explicitly shared ReadStream for the upload and does not close it. The response owns the upload work until response closure/completion: keep the input's scope open through the response scope. Under HTTP/1.1, streaming server responses enable full duplex so a response does not silently drain/close the outstanding upload. Upload faults retain source fault identity, not a generic transport success. Redirects requiring replay are returned to the caller for streaming bodies; immutable Bytes sends can follow configured redirects. A consumed prefix cannot be rolled back after failure.

### Redirects and HTTP status

Redirects honor max_redirects (zero returns the redirect response), reject TLS downgrade, recheck the Network policy on every destination, and remove explicit Authorization/Cookie/Proxy-Authorization when the origin changes. Automatic cookies are selected by the destination jar rather than copying source-origin headers. HTTP 4xx and 5xx statuses are returned responses, rather than transport errors. Header names/values reject injection and callers cannot set host-managed framing fields.

## Streaming request host

Call `Network.serve_stream` directly; it cannot be stored as a function value. Its handler must be proved safe to call concurrently and have type `fn(exchange: HttpExchange & Shareable) -> Result[Unit, HttpError]`. The server establishes a fixed request execution context, bounded admission, body/output/header limits, disconnect cancellation and timeout. The handler may read incrementally, emit headers once and write/flush bounded output, or upgrade to a WebSocket session. Route requests with ordinary branches on method and path.

### Response ordering and limits

Read and write have separate synchronized gates. Send_headers accepts status 200–599 and ordered duplicate header values; it rejects repeated headers emission, CR/LF/NUL values, and caller-supplied framing. Write requires headers first, counts cumulative output bytes, applies native backpressure and disallows bodies for HEAD/204/304. Body bound failures return IoError.Failed with a limit diagnostic. Before headers, handler faults/domain errors produce a generic 500, or 504 for timeout where possible; after headers the host aborts transport rather than returning a misleading complete body. Returning success without headers produces 204.

### Request and server lifetime

HttpExchange belongs to its request: retained aliases report Closed once request cleanup ends. Server shutdown stops admission, waits grace, cancels remaining requests/sessions and joins them before returning. Hijacked WebSocket transports are explicitly included in request cleanup and joining. A server or Network cannot close from its own handler. Streaming source code needs no new function kind or detached task syntax.

## Network operations

```text
fn request(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration) -> Result[ClientResponse, HttpError]
fn http_client(options: HttpClientOptions) -> Result[HttpClient&Shareable, HttpError]
fn serve_stream(address: String, handler: fn(exchange: HttpExchange&Shareable) -> Result[Unit, HttpError], options: HttpServerOptions) -> Result[HttpServer&Shareable, HttpError]
```
