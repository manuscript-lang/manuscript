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
    fn send(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration) -> Result[ResponseBody, LibraryError]
    fn send_stream(method: String, url: String, headers: Map[String, String], body: ReadStream, max_response_bytes: Int, timeout: Duration) -> Result[ResponseBody, LibraryError]
```

## HttpClientOptions {data-api-kind="Record"}

```manuscript
type HttpClientOptions:
    max_redirects: Int
    max_idle_connections: Int
    max_header_bytes: Int
    idle_timeout: Duration
    decompress: Bool
    cookies: Bool
    tls: TlsOptions
```

## HttpExchange {data-api-kind="Interface"}

```manuscript
interface HttpExchange:
    fn close() -> Unit
    fn headers() -> Map[String, List[String]]
    fn method() -> String
    fn path() -> String
    fn query() -> String
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
    fn send_headers(status: Int, headers: Map[String, List[String]]) -> Result[Unit, LibraryError]
    fn upgrade(allowed_origins: List[String], subprotocols: List[String], max_message_bytes: Int) -> Result[WebSocket, LibraryError]
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
    max_requests: Int
    max_body_bytes: Int
    max_response_bytes: Int
    max_header_bytes: Int
    timeout: Duration
    grace: Duration
    tls: Optional[TlsOptions]
```

## Network {data-api-kind="Interface"}

```manuscript
interface Network:
    fn bind_datagram(address: String) -> Result[DatagramSocket, LibraryError]
    fn close() -> Unit
    fn connect(address: String, timeout: Duration) -> Result[Connection, LibraryError]
    fn connect_tls(address: String, server_name: String, timeout: Duration) -> Result[Connection, LibraryError]
    fn connect_tls_config(address: String, options: TlsOptions, timeout: Duration) -> Result[Connection, LibraryError]
    fn connect_unix(path: String, timeout: Duration) -> Result[Connection, LibraryError]
    fn http_client(options: HttpClientOptions) -> Result[HttpClient, LibraryError]
    fn listen(address: String) -> Result[Listener, LibraryError]
    fn listen_tls(address: String, options: TlsOptions, handshake_timeout: Duration) -> Result[Listener, LibraryError]
    fn listen_unix(path: String) -> Result[Listener, LibraryError]
    fn lookup(name: String, max_records: Int, timeout: Duration) -> Result[List[String], LibraryError]
    fn request(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration) -> Result[ClientResponse, LibraryError]
    fn resolve(name: String, kind: String, max_records: Int, timeout: Duration) -> Result[List[DnsRecord], LibraryError]
    fn restrict(hosts: List[String], cidrs: List[String], allow_listen: Bool) -> Result[Network, LibraryError]
    fn serve(address: String, handler: fn(request: HttpRequest) -> HttpResponse, limit: Int, max_body_bytes: Int, max_response_bytes: Int, timeout: Duration, grace: Duration) -> Result[HttpServer, IoError]
    fn serve_stream(address: String, handler: fn(exchange: HttpExchange) -> Result[Unit, LibraryError], options: HttpServerOptions) -> Result[HttpServer, LibraryError]
    fn web_socket(url: String, headers: Map[String, String], subprotocols: List[String], options: WebSocketOptions) -> Result[WebSocket, LibraryError]
    fn with_resolver(address: String) -> Result[Network, LibraryError]
```

## ResponseBody {data-api-kind="Interface"}

```manuscript
interface ResponseBody:
    fn close() -> Unit
    fn headers() -> Map[String, List[String]]
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
    fn status() -> Int
```

