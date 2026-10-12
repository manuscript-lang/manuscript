+++
title = "http"
+++

# @std/http.ms

Import each required symbol with `import Name from "@std/http.ms"`.

## ClientResponse

Kind: record.

```text
ClientResponse: ClientResponse
field status: Int
field headers: Map[String, List[String]]
field body: Bytes
```

## HttpClient

Kind: interface.

```text
HttpClient: HttpClient
operation close: fn()->Unit
operation send: fn(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration)->Result[ResponseBody & Shareable, HttpError]
operation send_stream: fn(method: String, url: String, headers: Map[String, String], body: ReadStream & Shareable, max_response_bytes: Int, timeout: Duration)->Result[ResponseBody & Shareable, HttpError]
```

## HttpClientOptions

Kind: record.

```text
HttpClientOptions: HttpClientOptions
field max_redirects: Int
field max_idle_connections: Int
field max_header_bytes: Int
field idle_timeout: Duration
field decompress: Bool
field cookies: Bool
field tls: TlsOptions
```

## HttpError

Kind: alternative.

```text
HttpError: HttpError
implements: Error
case InvalidInput
case InvalidData
case LimitExceeded
case PermissionDenied
case Closed
case Timeout
case Failed(message: String)
operation message: fn()->String
```

## HttpExchange

Kind: interface.

```text
HttpExchange: HttpExchange
operation close: fn()->Unit
operation headers: fn()->Map[String, List[String]]
operation method: fn()->String
operation path: fn()->String
operation query: fn()->String
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
operation send_headers: fn(status: Int, headers: Map[String, List[String]])->Result[Unit, HttpError]
operation upgrade: fn(allowed_origins: List[String], subprotocols: List[String], max_message_bytes: Int)->Result[WebSocket & Shareable, WebSocketError]
operation write: fn(data: Bytes)->Result[Unit, IoError]
```

## HttpRequest

Kind: record.

```text
HttpRequest: HttpRequest
field method: String
field path: String
field query: String
field headers: Map[String, Bytes]
field body: Bytes
```

## HttpResponse

Kind: record.

```text
HttpResponse: HttpResponse
field status: Int
field headers: Map[String, String]
field body: Bytes
```

## HttpServer

Kind: interface.

```text
HttpServer: HttpServer
operation address: fn()->String
operation close: fn()->Unit
operation wait: fn()->Result[Unit, IoError]
```

## HttpServerOptions

Kind: record.

```text
HttpServerOptions: HttpServerOptions
field max_requests: Int
field max_body_bytes: Int
field max_response_bytes: Int
field max_header_bytes: Int
field timeout: Duration
field grace: Duration
field tls: Optional[TlsOptions]
```

## Network

Kind: interface.

```text
Network: Network
operation bind_datagram: fn(address: String)->Result[DatagramSocket & Shareable, NetworkError]
operation close: fn()->Unit
operation connect: fn(address: String, timeout: Duration)->Result[Connection & Shareable, NetworkError]
operation connect_tls: fn(address: String, server_name: String, timeout: Duration)->Result[Connection & Shareable, NetworkError]
operation connect_tls_config: fn(address: String, options: TlsOptions, timeout: Duration)->Result[Connection & Shareable, NetworkError]
operation connect_unix: fn(path: String, timeout: Duration)->Result[Connection & Shareable, NetworkError]
operation http_client: fn(options: HttpClientOptions)->Result[HttpClient & Shareable, HttpError]
operation listen: fn(address: String)->Result[Listener & Shareable, NetworkError]
operation listen_tls: fn(address: String, options: TlsOptions, handshake_timeout: Duration)->Result[Listener & Shareable, NetworkError]
operation listen_unix: fn(path: String)->Result[Listener & Shareable, NetworkError]
operation lookup: fn(name: String, max_records: Int, timeout: Duration)->Result[List[String], NetworkError]
operation request: fn(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration)->Result[ClientResponse, HttpError]
operation resolve: fn(name: String, kind: String, max_records: Int, timeout: Duration)->Result[List[DnsRecord], NetworkError]
operation restrict: fn(hosts: List[String], cidrs: List[String], allow_listen: Bool)->Result[Network & Shareable, NetworkError]
operation serve: fn(address: String, handler: fn(request: HttpRequest)->HttpResponse, limit: Int, max_body_bytes: Int, max_response_bytes: Int, timeout: Duration, grace: Duration)->Result[HttpServer & Shareable, IoError]
operation serve_stream: fn(address: String, handler: fn(exchange: HttpExchange & Shareable)->Result[Unit, HttpError], options: HttpServerOptions)->Result[HttpServer & Shareable, HttpError]
operation web_socket: fn(url: String, headers: Map[String, String], subprotocols: List[String], options: WebSocketOptions)->Result[WebSocket & Shareable, WebSocketError]
operation with_resolver: fn(address: String)->Result[Network & Shareable, NetworkError]
```

## ResponseBody

Kind: interface.

```text
ResponseBody: ResponseBody
operation close: fn()->Unit
operation headers: fn()->Map[String, List[String]]
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
operation status: fn()->Int
```

