+++
title = "HTTP"
weight = 56
+++

# HTTP

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Use HttpClient for reusable outbound requests and HttpExchange for streaming request handling. Response bodies are resources: read them in chunks and close them. A received HTTP error status is still a response you can inspect.

## `@std/http.ms`

## HttpClient operations

```manuscript
fn send(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Optional[Int], timeout: Optional[Duration]) -> Result[ResponseBody, HttpError]
fn send_stream(method: String, url: String, headers: Map[String, String], body: ReadStream, max_response_bytes: Optional[Int], timeout: Optional[Duration]) -> Result[ResponseBody, HttpError]
fn close() -> Unit
```

## ResponseBody operations

```manuscript
fn status() -> Int
fn headers() -> Map[String, List[String]]
fn read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]
fn close() -> Unit
```

## HttpExchange operations

```manuscript
fn method() -> String
fn path() -> String
fn query() -> String
fn headers() -> Map[String, List[String]]
fn read(max_bytes: Optional[Int]) -> Result[Optional[Bytes], IoError]
fn send_headers(status: Int, headers: Map[String, List[String]]) -> Result[Unit, HttpError]
fn write(data: Bytes) -> Result[Unit, IoError]
fn upgrade(allowed_origins: List[String], subprotocols: List[String], max_message_bytes: Optional[Int]) -> Result[WebSocket, WebSocketError]
fn close() -> Unit
```

## Compatibility

Network.serve handles buffered requests, and Network.request returns a buffered response. Reusable clients and streaming servers support HTTP/1.1 and HTTP/2 with the same HTTP record types. HTTP/3 is excluded by user instruction.

## Configuration

```manuscript
type HttpClientOptions:
    max_redirects: Optional[Int]
    max_idle_connections: Optional[Int]
    max_header_bytes: Optional[Int]
    idle_timeout: Optional[Duration]
    decompress: Bool
    cookies: Bool
    tls: TlsOptions

type HttpServerOptions:
    max_requests: Optional[Int]
    max_body_bytes: Optional[Int]
    max_response_bytes: Optional[Int]
    max_header_bytes: Optional[Int]
    timeout: Optional[Duration]
    grace: Optional[Duration]
    tls: Optional[TlsOptions]
```

### Option limits

Limits and deadlines are optional. Supplied redirect counts, idle capacity, byte budgets, deadlines, and grace must be nonnegative; supplied header and request-admission caps must be positive. With no TLS configuration, the server uses plain HTTP/1.1. With TLS configured, native ALPN negotiation selects HTTP/1.1 or HTTP/2. Credentials/trust come from explicit TlsOptions. No ambient HTTP proxy is read.

### Client lifetime

Create a shared HttpClient through `Network.http_client`. It implements Closeable, so keep it in a `with` scope. It owns a pooled transport and optional public-suffix-aware cookie jar. Idle connections and lifetime are explicit options. Close stops admission, cancels in-flight requests, closes outstanding response bodies, joins their upload/read work and releases idle connections. Network close owns and joins clients too.

### Reading a response

`send` returns a ResponseBody that you read incrementally. Reads follow the stream contract. `max_response_bytes` limits the cumulative decoded output. Status and duplicate headers remain available as metadata. Close before EOF cancels/discards the body; consumed bodies can reuse the pooled connection. Timeout covers DNS through body lifetime; parent cancellation unwinds. Gzip decoding is enabled only with decompress and remains subject to the expanded-byte bound. Invalid UTF-8 header values are rejected before constructing source Strings.

### Streaming an upload

Send_stream borrows an explicitly shared ReadStream for the upload and does not close it. The response owns the upload work until response closure/completion: keep the input's scope open through the response scope. Under HTTP/1.1, streaming server responses enable full duplex so a response does not silently drain/close the outstanding upload. Upload faults retain source fault identity, not a generic transport success. Redirects requiring replay are returned to the caller for streaming bodies; immutable Bytes sends can follow configured redirects. A consumed prefix cannot be rolled back after failure.

### Redirects and HTTP status

Redirects honor max_redirects (zero returns the redirect response), reject TLS downgrade, recheck the Network policy on every destination, and remove explicit Authorization/Cookie/Proxy-Authorization when the origin changes. Automatic cookies are selected by the destination jar rather than copying source-origin headers. HTTP 4xx and 5xx statuses are returned responses, rather than transport errors. Header names/values reject injection and callers cannot set host-managed framing fields.

## Request API

`Network` and `network()` are exported by `@std/net.ms`. Buffered request/response records, streaming exchanges, and server types live in `@std/http.ms`.

`Network.serve` accepts `fn(request: HttpRequest) -> HttpResponse` and returns a scoped HttpServer. Request headers are bytes, the raw query stays encoded, and source code routes by ordinary method/path branching. Responses require status 200–599, valid header names and values, and a body within any supplied response budget. See [the Network reference](../reference/net.md#network) for its exact optional admission, byte, deadline, and grace parameters.

Client disconnection cancels the request and nested task-group work. Started work joins and registered cleanup runs before the request ends. Handler faults become 500 responses and reach diagnostics; deadline expiry produces 504 where the transport permits it. Oversized buffered request bodies receive 413, and excess admission under a supplied cap receives 503 without invoking a handler.

Schedulers used by handlers retain their construction lifetime. Accepted work uses that scheduler's context rather than the submitting request's deadline or disconnect signal. Construct shared schedulers outside request scopes, keep their dependencies open, and acquire operation resources inside each callback. Close them before releasing application resources.

## Streaming request servers

Network.serve_stream accepts an ordinary handler and may be stored as a bound method. The handler signature is `fn(exchange: HttpExchange) -> Result[Unit, HttpError]`. The server establishes a fixed request execution context, optional admission and body/output/header budgets, disconnect cancellation, and an optional timeout. The handler may read incrementally, emit headers once and write/flush bounded output, or upgrade to a WebSocket session. Source routes by ordinary method/path branching.

### Response ordering and limits

Read and write have separate synchronized gates. Send_headers accepts status 200–599 and ordered duplicate header values; it rejects repeated headers emission, CR/LF/NUL values, and caller-supplied framing. Write requires headers first, counts cumulative output bytes, applies native backpressure and disallows bodies for HEAD/204/304. Body bound failures return IoError.Failed with a limit diagnostic. Before headers, handler faults/domain errors produce a generic 500, or 504 for timeout where possible; after headers the host aborts transport rather than returning a misleading complete body. Returning success without headers produces 204.

### Request and server lifetime

HttpExchange belongs to its request: retained aliases report Closed once request cleanup ends. Server shutdown stops admission, waits grace, cancels remaining requests/sessions and joins them before returning. Hijacked WebSocket transports are explicitly included in request cleanup and joining. A server or Network cannot close from its own handler. Streaming source code needs no new function kind or detached task syntax.

## Network operations

```manuscript
fn request(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Optional[Int], timeout: Optional[Duration]) -> Result[ClientResponse, HttpError]
fn http_client(options: HttpClientOptions) -> Result[HttpClient, HttpError]
fn serve_stream(address: String, handler: fn(exchange: HttpExchange) -> Result[Unit, HttpError], options: HttpServerOptions) -> Result[HttpServer, HttpError]
```
