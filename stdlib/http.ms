# Canonical standard-library declarations. Implementations are native.

import Bytes from "@std/bytes.ms"
import Connection from "@std/net.ms"
import DatagramSocket from "@std/net.ms"
import DnsRecord from "@std/net.ms"
import Duration from "@std/time.ms"
import IoError from "@std/io.ms"
import LibraryError from "@std/errors.ms"
import List from "@std/collections.ms"
import Listener from "@std/net.ms"
import Map from "@std/collections.ms"
import Optional from "@std/optional.ms"
import ReadStream from "@std/io.ms"
import Result from "@std/result.ms"
import TlsOptions from "@std/tls.ms"
import WebSocket from "@std/websocket.ms"
import WebSocketOptions from "@std/websocket.ms"

export type ClientResponse:
    status: Int
    headers: Map[String, List[String]]
    body: Bytes

export type HttpClient:
    fn close() -> Unit
    fn send(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration) -> Result[ResponseBody & Shareable, LibraryError]
    fn send_stream(method: String, url: String, headers: Map[String, String], body: ReadStream & Shareable, max_response_bytes: Int, timeout: Duration) -> Result[ResponseBody & Shareable, LibraryError]

export type HttpClientOptions:
    max_redirects: Int
    max_idle_connections: Int
    max_header_bytes: Int
    idle_timeout: Duration
    decompress: Bool
    cookies: Bool
    tls: TlsOptions

export type HttpExchange:
    fn close() -> Unit
    fn headers() -> Map[String, List[String]]
    fn method() -> String
    fn path() -> String
    fn query() -> String
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
    fn send_headers(status: Int, headers: Map[String, List[String]]) -> Result[Unit, LibraryError]
    fn upgrade(allowed_origins: List[String], subprotocols: List[String], max_message_bytes: Int) -> Result[WebSocket & Shareable, LibraryError]
    fn write(data: Bytes) -> Result[Unit, IoError]

export type HttpRequest:
    method: String
    path: String
    query: String
    headers: Map[String, Bytes]
    body: Bytes

export type HttpResponse:
    status: Int
    headers: Map[String, String]
    body: Bytes

export type HttpServer:
    fn address() -> String
    fn close() -> Unit
    fn wait() -> Result[Unit, IoError]

export type HttpServerOptions:
    max_requests: Int
    max_body_bytes: Int
    max_response_bytes: Int
    max_header_bytes: Int
    timeout: Duration
    grace: Duration
    tls: Optional[TlsOptions]

export type Network:
    fn bind_datagram(address: String) -> Result[DatagramSocket & Shareable, LibraryError]
    fn close() -> Unit
    fn connect(address: String, timeout: Duration) -> Result[Connection & Shareable, LibraryError]
    fn connect_tls(address: String, server_name: String, timeout: Duration) -> Result[Connection & Shareable, LibraryError]
    fn connect_tls_config(address: String, options: TlsOptions, timeout: Duration) -> Result[Connection & Shareable, LibraryError]
    fn connect_unix(path: String, timeout: Duration) -> Result[Connection & Shareable, LibraryError]
    fn http_client(options: HttpClientOptions) -> Result[HttpClient & Shareable, LibraryError]
    fn listen(address: String) -> Result[Listener & Shareable, LibraryError]
    fn listen_tls(address: String, options: TlsOptions, handshake_timeout: Duration) -> Result[Listener & Shareable, LibraryError]
    fn listen_unix(path: String) -> Result[Listener & Shareable, LibraryError]
    fn lookup(name: String, max_records: Int, timeout: Duration) -> Result[List[String], LibraryError]
    fn request(method: String, url: String, headers: Map[String, String], body: Bytes, max_response_bytes: Int, timeout: Duration) -> Result[ClientResponse, LibraryError]
    fn resolve(name: String, kind: String, max_records: Int, timeout: Duration) -> Result[List[DnsRecord], LibraryError]
    fn restrict(hosts: List[String], cidrs: List[String], allow_listen: Bool) -> Result[Network & Shareable, LibraryError]
    fn serve(address: String, handler: fn(request: HttpRequest) -> HttpResponse, limit: Int, max_body_bytes: Int, max_response_bytes: Int, timeout: Duration, grace: Duration) -> Result[HttpServer & Shareable, IoError]
    fn serve_stream(address: String, handler: fn(exchange: HttpExchange & Shareable) -> Result[Unit, LibraryError], options: HttpServerOptions) -> Result[HttpServer & Shareable, LibraryError]
    fn web_socket(url: String, headers: Map[String, String], subprotocols: List[String], options: WebSocketOptions) -> Result[WebSocket & Shareable, LibraryError]
    fn with_resolver(address: String) -> Result[Network & Shareable, LibraryError]

export type ResponseBody:
    fn close() -> Unit
    fn headers() -> Map[String, List[String]]
    fn read(max_bytes: Int) -> Result[Optional[Bytes], IoError]
    fn status() -> Int
