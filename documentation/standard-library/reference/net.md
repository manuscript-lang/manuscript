+++
title = "net"
+++

# @std/net.ms

Import each required symbol with `import Name from "@std/net.ms"`.

## Connection {data-api-kind="Interface"}

```manuscript
interface Connection:
    fn close() -> Unit
    fn local_address() -> String
    fn peer_address() -> String
    fn read(max_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[Optional[Bytes], IoError]
    fn shutdown_write() -> Result[Unit, NetworkError]
    fn tls_info() -> Result[TlsInfo, TlsError]
    fn write(data: Bytes, timeout: Optional[Duration] = none) -> Result[Unit, IoError]
```

## Datagram {data-api-kind="Record"}

```manuscript
type Datagram:
    data: Bytes
    sender: String
```

## DatagramSocket {data-api-kind="Interface"}

```manuscript
interface DatagramSocket:
    fn address() -> String
    fn close() -> Unit
    fn receive(max_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[Datagram, NetworkError]
    fn send(data: Bytes, address: String, timeout: Optional[Duration] = none) -> Result[Unit, NetworkError]
```

## DnsRecord {data-api-kind="Record"}

```manuscript
type DnsRecord:
    kind: String
    value: String
    priority: Int
    weight: Int
    port: Int
```

## Listener {data-api-kind="Interface"}

```manuscript
interface Listener:
    fn accept(timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
    fn address() -> String
    fn close() -> Unit
```

## Network {data-api-kind="Interface"}

```manuscript
interface Network:
    fn bind_datagram(address: String) -> Result[DatagramSocket, NetworkError]
    fn close() -> Unit
    fn connect(address: String, timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
    fn connect_tls(address: String, server_name: String, timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
    fn connect_tls_config(address: String, options: TlsOptions, timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
    fn connect_unix(path: String, timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
    fn http_client(options: HttpClientOptions) -> Result[HttpClient, HttpError]
    fn listen(address: String) -> Result[Listener, NetworkError]
    fn listen_tls(address: String, options: TlsOptions, handshake_timeout: Optional[Duration] = none) -> Result[Listener, NetworkError]
    fn listen_unix(path: String) -> Result[Listener, NetworkError]
    fn lookup(name: String, max_records: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[List[String], NetworkError]
    fn request(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ClientResponse, HttpError]
    fn resolve(name: String, kind: String, max_records: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[List[DnsRecord], NetworkError]
    fn restrict(hosts: List[String], cidrs: List[String], allow_listen: Bool) -> Result[Network, NetworkError]
    fn serve(address: String, handler: fn(request: HttpRequest) -> HttpResponse, limit: Optional[Int] = none, max_body_bytes: Optional[Int] = none, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none, grace: Optional[Duration] = none) -> Result[HttpServer, IoError]
    fn serve_stream(address: String, handler: fn(exchange: HttpExchange) -> Result[Unit, HttpError], options: HttpServerOptions) -> Result[HttpServer, HttpError]
    fn web_socket(url: String, headers: Map[String, String], subprotocols: List[String], options: WebSocketOptions) -> Result[WebSocket, WebSocketError]
    fn with_resolver(address: String) -> Result[Network, NetworkError]
```

## NetworkError {data-api-kind="Alternative"}

```manuscript
type NetworkError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case PermissionDenied
    case Unsupported
    case Closed
    case Timeout
    case Failed(message: String)
```

```manuscript
impl Error for NetworkError:
    fn message() -> String
```

## contains_ip {data-api-kind="Function"}

```manuscript
fn contains_ip(cidr: String, address: String) -> Result[Bool, NetworkError]
```

## network {data-api-kind="Function"}

```manuscript
fn network() -> Network
```

## parse_cidr {data-api-kind="Function"}

```manuscript
fn parse_cidr(text: String) -> Result[String, NetworkError]
```

## parse_ip {data-api-kind="Function"}

```manuscript
fn parse_ip(text: String) -> Result[String, NetworkError]
```

