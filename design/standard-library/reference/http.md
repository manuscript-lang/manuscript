+++
title = "http"
+++

# @std/http.ms

Import each required symbol with `import Name from "@std/http.ms"`.

## ClientResponse

Kind: record.

```manuscript
ClientResponse: ClientResponse
field status: Int
field headers: Map[String, List[String]]
field body: Bytes
```

## HttpClient

Kind: interface.

```manuscript
HttpClient: HttpClient
operation close: fn()->Unit
operation send: fn(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration)->Result[ResponseBody, LibraryError]
operation send_stream: fn(method: String, url: String, headers: Map[String, String], body: ReadStream, max_response_bytes: Int, timeout: Duration)->Result[ResponseBody, LibraryError]
```

## HttpClientOptions

Kind: record.

```manuscript
HttpClientOptions: HttpClientOptions
field max_redirects: Int
field max_idle_connections: Int
field max_header_bytes: Int
field idle_timeout: Duration
field decompress: Bool
field cookies: Bool
field tls: TlsOptions
```

## HttpExchange

Kind: interface.

```manuscript
HttpExchange: HttpExchange
operation close: fn()->Unit
operation headers: fn()->Map[String, List[String]]
operation method: fn()->String
operation path: fn()->String
operation query: fn()->String
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
operation send_headers: fn(status: Int, headers: Map[String, List[String]])->Result[Unit, LibraryError]
operation upgrade: fn(allowed_origins: List[String], subprotocols: List[String], max_message_bytes: Int)->Result[WebSocket, LibraryError]
operation write: fn(data: Bytes)->Result[Unit, IoError]
```

## HttpRequest

Kind: record.

```manuscript
HttpRequest: HttpRequest
field method: String
field path: String
field query: String
field headers: Map[String, Bytes]
field body: Bytes
```

## HttpResponse

Kind: record.

```manuscript
HttpResponse: HttpResponse
field status: Int
field headers: Map[String, String]
field body: Bytes
```

## HttpServer

Kind: interface.

```manuscript
HttpServer: HttpServer
operation address: fn()->String
operation close: fn()->Unit
operation wait: fn()->Result[Unit, IoError]
```

## HttpServerOptions

Kind: record.

```manuscript
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

```manuscript
Network: Network
operation bind_datagram: fn(address: String)->Result[DatagramSocket, LibraryError]
operation close: fn()->Unit
operation connect: fn(address: String, timeout: Duration)->Result[Connection, LibraryError]
operation connect_tls: fn(address: String, server_name: String, timeout: Duration)->Result[Connection, LibraryError]
operation connect_tls_config: fn(address: String, options: TlsOptions, timeout: Duration)->Result[Connection, LibraryError]
operation connect_unix: fn(path: String, timeout: Duration)->Result[Connection, LibraryError]
operation http_client: fn(options: HttpClientOptions)->Result[HttpClient, LibraryError]
operation listen: fn(address: String)->Result[Listener, LibraryError]
operation listen_tls: fn(address: String, options: TlsOptions, handshake_timeout: Duration)->Result[Listener, LibraryError]
operation listen_unix: fn(path: String)->Result[Listener, LibraryError]
operation lookup: fn(name: String, max_records: Int, timeout: Duration)->Result[List[String], LibraryError]
operation request: fn(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration)->Result[ClientResponse, LibraryError]
operation resolve: fn(name: String, kind: String, max_records: Int, timeout: Duration)->Result[List[DnsRecord], LibraryError]
operation restrict: fn(hosts: List[String], cidrs: List[String], allow_listen: Bool)->Result[Network, LibraryError]
operation serve: fn(address: String, handler: fn(request: HttpRequest)->HttpResponse, limit: Int, max_body_bytes: Int, max_response_bytes: Int, timeout: Duration, grace: Duration)->Result[HttpServer, IoError]
operation serve_stream: fn(address: String, handler: fn(exchange: HttpExchange)->Result[Unit, LibraryError], options: HttpServerOptions)->Result[HttpServer, LibraryError]
operation web_socket: fn(url: String, headers: Map[String, String], subprotocols: List[String], options: WebSocketOptions)->Result[WebSocket, LibraryError]
operation with_resolver: fn(address: String)->Result[Network, LibraryError]
```

## ResponseBody

Kind: interface.

```manuscript
ResponseBody: ResponseBody
operation close: fn()->Unit
operation headers: fn()->Map[String, List[String]]
operation read: fn(max_bytes: Int)->Result[Optional[Bytes], IoError]
operation status: fn()->Int
```

