+++
title = "http"
+++

# @std/http.ms

Import each required symbol with `import Name from "@std/http.ms"`.

## ClientResponse {data-api-kind="Record"}

```manuscript
type ClientResponse:
    status: Int
    headers: Map[String, List[String]]
    body: Bytes
```

## HttpClient {data-api-kind="Interface"}

```manuscript
interface HttpClient:
    fn close() -> Unit
    fn send(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
    fn send_stream(method: String, url: String, headers: Map[String, String], body: ReadStream, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ResponseBody, HttpError]
```

## HttpClientOptions {data-api-kind="Record"}

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

## HttpError {data-api-kind="Alternative"}

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
    fn message() -> String
```

## HttpExchange {data-api-kind="Interface"}

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

## HttpRequest {data-api-kind="Record"}

```manuscript
type HttpRequest:
    method: String
    path: String
    query: String
    headers: Map[String, Bytes]
    body: Bytes
```

## HttpResponse {data-api-kind="Record"}

```manuscript
type HttpResponse:
    status: Int
    headers: Map[String, String]
    body: Bytes
```

## HttpServer {data-api-kind="Interface"}

```manuscript
interface HttpServer:
    fn address() -> String
    fn close() -> Unit
    fn wait() -> Result[Unit, IoError]
```

## HttpServerOptions {data-api-kind="Record"}

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

## ResponseBody {data-api-kind="Interface"}

```manuscript
interface ResponseBody:
    fn close() -> Unit
    fn headers() -> Map[String, List[String]]
    fn read(max_bytes: Optional[Int] = none) -> Result[Optional[Bytes], IoError]
    fn status() -> Int
```

