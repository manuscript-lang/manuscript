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

## HttpResponse {data-api-kind="Record"}

Buffered response returned by the simple HTTP server handler.

```manuscript
type HttpResponse:
    status: Int
    headers: HttpHeaders
    body: Bytes
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

## ResponseBody {data-api-kind="Interface"}

Streaming response body returned by reusable HTTP client operations.
Metadata remains available after close and shares one mutable header object.

```manuscript
interface ResponseBody:
    fn close() -> Unit
    fn metadata() -> HttpResponseMetadata
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
```

### ResponseBody.metadata

Returns the response head (status and headers) without copying; it stays available after close.

```manuscript
fn metadata() -> HttpResponseMetadata
```

## headers {data-api-kind="Function"}

Creates empty mutable headers. No header values are joined or comma-combined.

```manuscript
fn headers() -> HttpHeaders:
```

