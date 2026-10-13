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

## HttpClient {data-api-kind="Interface"}

Reusable HTTP client with connection pooling and explicit response limits.
Outbound case-equivalent header keys append values in Map insertion order.

```manuscript
interface HttpClient:
    fn close() -> Unit
    fn send(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Optional[Int64] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
    fn send_stream(method: String, url: String, headers: Map[String, String], body: ReadStream, max_response_bytes: Optional[Int64] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
```

## HttpClientOptions {data-api-kind="Record"}

Connection, redirect, cookie, decompression, and TLS settings for an HTTP client.

```manuscript
type HttpClientOptions:
    max_redirects: Optional[Int] = none
    max_idle_connections: Optional[Int] = none
    max_header_bytes: Optional[Int64] = none
    idle_timeout: Optional[Duration] = none
    decompress: Bool
    cookies: Bool
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
    fn read(max_bytes: Optional[Int64] = none) -> Result[Optional[Bytes], IoError]
    fn send_headers(status: Int, headers: Map[String, List[String]]) -> Result[Unit, HttpError]
    fn upgrade(allowed_origins: List[String], subprotocols: List[String], max_message_bytes: Optional[Int64] = none) -> Result[WebSocket, WebSocketError]
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

## HttpServer {data-api-kind="Interface"}

A running HTTP server. Close it to stop accepting new requests.

```manuscript
interface HttpServer:
    fn address() -> String
    fn close() -> Unit
    fn wait() -> Result[Unit, IoError]
```

## HttpServerOptions {data-api-kind="Record"}

Request and response limits, deadlines, graceful shutdown, and TLS server settings.

```manuscript
type HttpServerOptions:
    max_requests: Optional[Int] = none
    max_body_bytes: Optional[Int64] = none
    max_response_bytes: Optional[Int64] = none
    max_header_bytes: Optional[Int64] = none
    timeout: Optional[Duration] = none
    grace: Optional[Duration] = none
    tls: Optional[TlsOptions]
```

## ResponseBody {data-api-kind="Interface"}

Streaming response body returned by HTTP client operations. Header names have
canonical spelling; Map lookup is case-sensitive. Lists keep received order.

```manuscript
interface ResponseBody:
    fn close() -> Unit
    fn headers() -> Map[String, List[String]]
    fn read(max_bytes: Optional[Int64] = none) -> Result[Optional[Bytes], IoError]
    fn status() -> Int
```

## header_values {data-api-kind="Function"}

Finds all values under ASCII case-equivalent names without changing Map keys.
Returns none if absent, or some(empty) for a present empty list. Copies list
membership and preserves Map insertion order followed by each list's order.

```manuscript
fn header_values(headers: Map[String, List[String]], name: String) -> Optional[List[String]]:
```

