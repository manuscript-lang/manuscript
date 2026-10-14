# Canonical standard-library declarations. Implementations are native.

import WebSocketError from "@std/websocket.ms"
import WebSocketOptions from "@std/websocket.ms"
import WebSocket from "@std/websocket.ms"
import TlsOptions from "@std/tls.ms"
import HttpServerOptions from "@std/http.ms"
import HttpExchange from "@std/http.ms"
import HttpServer from "@std/http.ms"
import HttpResponse from "@std/http.ms"
import HttpRequest from "@std/http.ms"
import ClientResponse from "@std/http.ms"
import HttpError from "@std/http.ms"
import HttpClientOptions from "@std/http.ms"
import HttpClient from "@std/http.ms"
import Map from "@std/collections.ms"
import List from "@std/collections.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import IoError from "@std/io.ms"
import TlsError from "@std/tls.ms"
import TlsInfo from "@std/tls.ms"

# Errors returned by socket, DNS, and network connection operations.
export type NetworkError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case PermissionDenied
    case Unsupported
    case Closed
    case Timeout
    case Failed(message: String)

# A connected stream socket, optionally protected by TLS.
export interface Connection:
    fn close() -> Unit
    fn local_address() -> String
    fn peer_address() -> String
    # Returns a positive chunk or none at EOF; local timeout uses IoError.Failed, not NetworkError.Timeout.
    fn read(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[Optional[Bytes], IoError]
    fn shutdown_write() -> Result[Unit, NetworkError]
    fn tls_info() -> Result[TlsInfo, TlsError]
    # Writes all bytes on success; failure can leave a prefix. Local timeout uses IoError.Failed.
    fn write(data: Bytes, timeout: Optional[Duration] = none) -> Result[Unit, IoError]

# One datagram and the address from which it was received.
export type Datagram:
    data: Bytes
    # Native host:port text, with bracketed IPv6 addresses.
    sender: String

# A connectionless socket for sending and receiving datagrams.
export interface DatagramSocket:
    fn address() -> String
    fn close() -> Unit
    fn receive(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[Datagram, NetworkError]
    fn send(
        data: Bytes,
        address: String,
        timeout: Optional[Duration] = none
    ) -> Result[Unit, NetworkError]

# DNS record data returned by a typed lookup.
export type DnsRecord:
    # Uppercase A, AAAA, CNAME, MX, NS, TXT, PTR, or SRV.
    kind: String
    value: String
    priority: Int
    weight: Int
    port: Int

# A listening socket that accepts incoming connections.
export interface Listener:
    fn accept(timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
    fn address() -> String
    fn close() -> Unit

# Reports whether an IP address belongs to a CIDR range.
export fn contains_ip(cidr: String, address: String) -> Result[Bool, NetworkError]:

# Validates and canonicalizes an IPv4 or IPv6 CIDR range.
export fn parse_cidr(text: String) -> Result[String, NetworkError]:

# Validates and canonicalizes an IPv4 or IPv6 address.
export fn parse_ip(text: String) -> Result[String, NetworkError]:

impl Error for NetworkError:
    fn message() -> String:

# Network, DNS, HTTP, and WebSocket operations for the current host.
export interface Network:
    fn bind_datagram(address: String) -> Result[DatagramSocket, NetworkError]
    fn close() -> Unit
    fn connect(
        address: String,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    fn connect_tls(
        address: String,
        server_name: String,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    fn connect_tls_config(
        address: String,
        options: TlsOptions,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    fn connect_unix(
        path: String,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    fn http_client(options: HttpClientOptions) -> Result[HttpClient, HttpError]
    fn listen(address: String) -> Result[Listener, NetworkError]
    fn listen_tls(
        address: String,
        options: TlsOptions,
        handshake_timeout: Optional[Duration] = none
    ) -> Result[Listener, NetworkError]
    fn listen_unix(path: String) -> Result[Listener, NetworkError]
    fn lookup(
        name: String,
        max_records: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[List[String], NetworkError]
    fn request(
        method: String,
        url: String,
        headers: Map[String, String],
        body: Bytes,
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[ClientResponse, HttpError]
    # Accepts A, AAAA, CNAME, MX, NS, TXT, PTR, or SRV, case-insensitively; others return InvalidInput.
    # Returned DnsRecord.kind is uppercase.
    fn resolve(
        name: String,
        kind: String,
        max_records: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[List[DnsRecord], NetworkError]
    fn restrict(
        hosts: List[String],
        cidrs: List[String],
        allow_listen: Bool
    ) -> Result[Network, NetworkError]
    fn serve(
        address: String,
        handler: fn(request: HttpRequest) -> HttpResponse,
        limit: Optional[Int] = none,
        max_body_bytes: Optional[Int] = none,
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none,
        grace: Optional[Duration] = none
    ) -> Result[HttpServer, IoError]
    fn serve_stream(
        address: String,
        handler: fn(exchange: HttpExchange) -> Result[Unit, HttpError],
        options: HttpServerOptions
    ) -> Result[HttpServer, HttpError]
    fn web_socket(
        url: String,
        headers: Map[String, String],
        subprotocols: List[String],
        options: WebSocketOptions
    ) -> Result[WebSocket, WebSocketError]
    fn with_resolver(address: String) -> Result[Network, NetworkError]

# Returns network operations for the current host.
export fn network() -> Network:
