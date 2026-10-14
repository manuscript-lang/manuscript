+++
title = "net"
+++

# @std/net.ms

Import each required symbol with `import Name from "@std/net.ms"`.

## Cidr {data-api-kind="Native type"}

A validated, masked numeric CIDR range.

```manuscript
type Cidr:
    fn text() -> String:
```

### Cidr.text

Returns the canonical masked prefix without reparsing.

```manuscript
fn text() -> String:
```

## Connection {data-api-kind="Interface"}

A connected stream socket, optionally protected by TLS.

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

### Connection.close

Closes the socket, interrupting calls in progress, and waits for them to stop.
Safe to call repeatedly; later calls wait for the first. Reads and writes afterwards return Closed.

```manuscript
fn close() -> Unit
```

### Connection.local_address

Returns this end's address as `host:port` text, with IPv6 hosts in brackets; for Unix sockets it is the socket path.

```manuscript
fn local_address() -> String
```

### Connection.peer_address

Returns the remote end's address as `host:port` text, with IPv6 hosts in brackets.

```manuscript
fn peer_address() -> String
```

### Connection.read

Returns a positive chunk or none at EOF; local timeout uses IoError.Failed, not NetworkError.Timeout.

```manuscript
fn read(max_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[Optional[Bytes], IoError]
```

### Connection.shutdown_write

Half-closes the connection so the peer sees end of stream, while this side can keep reading.
Returns Unsupported for stream kinds that cannot half-close, and Closed on a closed connection.

```manuscript
fn shutdown_write() -> Result[Unit, NetworkError]
```

### Connection.tls_info

Returns the negotiated TLS version, cipher suite, protocol, and peer certificates.
A connection that is not TLS returns InvalidInput.

```manuscript
fn tls_info() -> Result[TlsInfo, TlsError]
```

### Connection.write

Writes all bytes on success; failure can leave a prefix. Local timeout uses IoError.Failed.

```manuscript
fn write(data: Bytes, timeout: Optional[Duration] = none) -> Result[Unit, IoError]
```

## Datagram {data-api-kind="Record"}

One datagram and the address from which it was received.

```manuscript
type Datagram:
    data: Bytes
    sender: String
```

### Datagram.data

The payload bytes of this datagram, never longer than the receive call's `max_bytes`.

```manuscript
data: Bytes
```

### Datagram.sender

Native host:port text, with bracketed IPv6 addresses.

```manuscript
sender: String
```

## DatagramSocket {data-api-kind="Interface"}

A connectionless socket for sending and receiving datagrams.

```manuscript
interface DatagramSocket:
    fn address() -> String
    fn close() -> Unit
    fn receive(max_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[Datagram, NetworkError]
    fn send(data: Bytes, address: String, timeout: Optional[Duration] = none) -> Result[Unit, NetworkError]
```

### DatagramSocket.address

Returns the bound local address as `host:port` text, which reveals the port chosen when binding port 0.

```manuscript
fn address() -> String
```

### DatagramSocket.close

Closes the socket, interrupting calls in progress, and waits for them to stop.
Safe to call repeatedly.

```manuscript
fn close() -> Unit
```

### DatagramSocket.receive

Waits for one datagram and returns its bytes with the sender's address. `max_bytes` is 1 through 65535 and defaults to 65535.
A larger datagram returns LimitExceeded and is discarded. A timeout returns Timeout and a closed socket returns Closed.

```manuscript
fn receive(max_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[Datagram, NetworkError]
```

### DatagramSocket.send

Sends `data` as a single datagram to `address` (`host:port`), resolving a host name with the network's resolver.
The network's restrictions apply to both the name and the resolved address. A short send returns Failed; a timeout returns Timeout.

```manuscript
fn send(data: Bytes, address: String, timeout: Optional[Duration] = none) -> Result[Unit, NetworkError]
```

## DnsKind {data-api-kind="Alternative"}

Supported DNS query categories; unknown spellings are rejected by checking.

```manuscript
type DnsKind:
    case A
    case AAAA
    case CNAME
    case MX
    case NS
    case TXT
    case PTR
    case SRV
    fn text() -> String:
```

### DnsKind.A

IPv4 address records for the queried name.

```manuscript
case A
```

### DnsKind.AAAA

IPv6 address records for the queried name.

```manuscript
case AAAA
```

### DnsKind.CNAME

Canonical name alias records for the queried name.

```manuscript
case CNAME
```

### DnsKind.MX

Mail exchange records with priority values.

```manuscript
case MX
```

### DnsKind.NS

Name server records for the queried zone.

```manuscript
case NS
```

### DnsKind.PTR

Reverse address pointer records for an IP.

```manuscript
case PTR
```

### DnsKind.SRV

Service location records with priority, weight and port.

```manuscript
case SRV
```

### DnsKind.TXT

Text records returned as string values.

```manuscript
case TXT
```

### DnsKind.text

Returns the uppercase wire category.

```manuscript
fn text() -> String:
```

## DnsRecord {data-api-kind="Record"}

DNS record data returned by a typed lookup.

```manuscript
type DnsRecord:
    kind: DnsKind
    value: String
    priority: Int
    weight: Int
    port: Int
```

### DnsRecord.kind

The same typed category used by the query.

```manuscript
kind: DnsKind
```

### DnsRecord.port

The service port of an SRV record; 0 for other kinds.

```manuscript
port: Int
```

### DnsRecord.priority

The preference of an MX record or the priority of an SRV record, where lower values are tried first; 0 for other kinds.

```manuscript
priority: Int
```

### DnsRecord.value

The record's answer: an IP address for A and AAAA, the target host name for CNAME, MX, NS, PTR, and SRV, or the text for TXT.

```manuscript
value: String
```

### DnsRecord.weight

The relative weight of an SRV record among targets with the same priority; 0 for other kinds.

```manuscript
weight: Int
```

## IpAddress {data-api-kind="Native type"}

A validated numeric IPv4/IPv6 address without a port or zone.

```manuscript
type IpAddress:
    fn text() -> String:
    fn family() -> IpFamily:
```

### IpAddress.family

Returns the normalized address family.

```manuscript
fn family() -> IpFamily:
```

### IpAddress.text

Returns canonical text; mapped IPv6 input is normalized to IPv4.

```manuscript
fn text() -> String:
```

## IpFamily {data-api-kind="Alternative"}

Numeric address families reported by IP values and host interfaces.

```manuscript
type IpFamily:
    case IPv4
    case IPv6
    fn text() -> String:
```

### IpFamily.IPv4

A four-byte numeric address.

```manuscript
case IPv4
```

### IpFamily.IPv6

A sixteen-byte numeric address.

```manuscript
case IPv6
```

### IpFamily.text

Returns IPv4 or IPv6.

```manuscript
fn text() -> String:
```

## Listener {data-api-kind="Interface"}

A listening socket that accepts incoming connections.

```manuscript
interface Listener:
    fn accept(timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
    fn address() -> String
    fn close() -> Unit
```

### Listener.accept

Waits for the next incoming connection and returns it. A timeout returns Timeout and a closed listener returns Closed.
On a TLS listener the handshake completes before the connection is returned; a failed handshake drops that connection and returns Failed.

```manuscript
fn accept(timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
```

### Listener.address

Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.

```manuscript
fn address() -> String
```

### Listener.close

Stops accepting, interrupts a pending `accept`, and waits for it to stop.
Safe to call repeatedly; connections already accepted stay open.

```manuscript
fn close() -> Unit
```

## Network {data-api-kind="Interface"}

Network, DNS, HTTP, and WebSocket operations for the current host.

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
    fn request(method: HttpMethod, url: String, headers: HttpHeaders, body: Bytes = "".to_bytes(), max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ClientResponse, HttpError]
    fn resolve(name: String, kind: DnsKind, max_records: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[List[DnsRecord], NetworkError]
    fn restrict(hosts: List[String], cidrs: List[String], allow_listen: Bool) -> Result[Network, NetworkError]
    fn serve(address: String, handler: fn(request: HttpRequest) -> HttpResponse, max_requests: Optional[Int] = none, max_body_bytes: Optional[Int] = none, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none, grace: Optional[Duration] = none) -> Result[HttpServer, IoError]
    fn serve_stream(address: String, handler: fn(exchange: HttpExchange) -> Result[Unit, HttpError], options: HttpServerOptions) -> Result[HttpServer, HttpError]
    fn web_socket(url: String, headers: HttpHeaders, subprotocols: List[String], options: WebSocketOptions) -> Result[WebSocket, WebSocketError]
    fn with_resolver(address: String) -> Result[Network, NetworkError]
```

### Network.bind_datagram

Binds a UDP socket to `address` (`host:port`; port 0 picks a free port).
A restricted network without listening permission, or an address outside its CIDRs, returns PermissionDenied.

```manuscript
fn bind_datagram(address: String) -> Result[DatagramSocket, NetworkError]
```

### Network.close

Cancels in-flight calls and closes every connection, listener, socket, HTTP client, and server this network opened, including those of derived networks.
Safe to call repeatedly. A request handler of a server on this network cannot close it and faults.

```manuscript
fn close() -> Unit
```

### Network.connect

Resolves `address` (`host:port`) and opens a TCP connection to the first reachable permitted address.
Returns PermissionDenied for names or addresses a restricted network disallows, Timeout when `timeout` elapses, and Failed when every address refuses.

```manuscript
fn connect(address: String, timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
```

### Network.connect_tls

Connects over TCP to `address` and completes a TLS handshake verifying the server certificate against the system roots for `server_name`, with at least TLS 1.2.
An empty `server_name` returns InvalidInput, and `timeout` bounds the whole attempt.

```manuscript
fn connect_tls(address: String, server_name: String, timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
```

### Network.connect_tls_config

Connects over TCP to `address` and completes a TLS handshake using `options`, with at least TLS 1.2.
Invalid options return InvalidInput, handshake and verification failures return Failed, and `timeout` bounds the whole attempt.

```manuscript
fn connect_tls_config(address: String, options: TlsOptions, timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
```

### Network.connect_unix

Connects to the Unix domain socket at `path`.
Any restricted network returns PermissionDenied because Unix sockets bypass host and CIDR checks. `timeout` bounds the attempt.

```manuscript
fn connect_unix(path: String, timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
```

### Network.http_client

Creates a reusable HTTP client with connection pooling that dials through this network, so its restrictions and resolver apply to every request and redirect.
Invalid or negative options return InvalidInput. Closing the network closes the client.

```manuscript
fn http_client(options: HttpClientOptions) -> Result[HttpClient, HttpError]
```

### Network.listen

Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
A restricted network needs `allow_listen` and an IP-literal address inside its CIDRs, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.

```manuscript
fn listen(address: String) -> Result[Listener, NetworkError]
```

### Network.listen_tls

Listens for TCP connections on `address` and completes a TLS handshake for each accepted connection, within `handshake_timeout` when supplied.
`options` must hold a certificate and key, otherwise InvalidInput is returned.

```manuscript
fn listen_tls(address: String, options: TlsOptions, handshake_timeout: Optional[Duration] = none) -> Result[Listener, NetworkError]
```

### Network.listen_unix

Listens on a Unix domain socket at `path`.
Any restricted network returns PermissionDenied.

```manuscript
fn listen_unix(path: String) -> Result[Listener, NetworkError]
```

### Network.lookup

Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
More than `max_records` addresses returns LimitExceeded, `timeout` bounds the lookup, and a failed lookup returns Failed.

```manuscript
fn lookup(name: String, max_records: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[List[String], NetworkError]
```

### Network.request

Performs one buffered HTTP request and returns the status, headers, and complete body.
Only `http` and `https` URLs without user info are accepted. Redirects are returned, not followed, and no cookies or proxy settings apply. A body over `max_response_bytes` returns LimitExceeded; error statuses are ordinary responses.

```manuscript
fn request(method: HttpMethod, url: String, headers: HttpHeaders, body: Bytes = "".to_bytes(), max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[ClientResponse, HttpError]
```

### Network.resolve

Resolves the selected supported category, retaining it in each record.

```manuscript
fn resolve(name: String, kind: DnsKind, max_records: Optional[Int] = none, timeout: Optional[Duration] = none) -> Result[List[DnsRecord], NetworkError]
```

### Network.restrict

Returns a derived network limited to the given host names and CIDR ranges.
Names match case-insensitively without a trailing dot, and IP-literal hosts also match through `cidrs`. With `cidrs`, every resolved address must be inside one of them. `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A derived restriction can only narrow its parent, and closing the parent closes the child. Invalid host or CIDR text returns InvalidInput.

```manuscript
fn restrict(hosts: List[String], cidrs: List[String], allow_listen: Bool) -> Result[Network, NetworkError]
```

### Network.serve

Starts an HTTP server on `address` that calls `handler` with each fully buffered request and sends the returned response.
A request beyond `limit` concurrent requests is answered with 503, an oversized request body with 413, and a handler fault with 500. An address that cannot be bound returns IoError.Unavailable.

```manuscript
fn serve(address: String, handler: fn(request: HttpRequest) -> HttpResponse, max_requests: Optional[Int] = none, max_body_bytes: Optional[Int] = none, max_response_bytes: Optional[Int] = none, timeout: Optional[Duration] = none, grace: Optional[Duration] = none) -> Result[HttpServer, IoError]
```

### Network.serve_stream

Starts an HTTP server on `address` whose handler receives each request as a streaming exchange. Limits, timeouts, and TLS come from `options`.
Returns PermissionDenied when a restricted network disallows listening, and InvalidInput for invalid options. Close the server to stop it.

```manuscript
fn serve_stream(address: String, handler: fn(exchange: HttpExchange) -> Result[Unit, HttpError], options: HttpServerOptions) -> Result[HttpServer, HttpError]
```

### Network.web_socket

Opens a WebSocket client connection to a `ws` or `wss` URL, sending the given headers and offering `subprotocols` in order.
Handshake headers such as `Upgrade`, `Connection`, `Host`, and `Sec-WebSocket-*` cannot be set. Failures use WebSocketError.

```manuscript
fn web_socket(url: String, headers: HttpHeaders, subprotocols: List[String], options: WebSocketOptions) -> Result[WebSocket, WebSocketError]
```

### Network.with_resolver

Returns a derived network that resolves names through the DNS server at `address`, an IP literal with port, instead of the system resolver.
The address must be allowed by this network's restrictions, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.

```manuscript
fn with_resolver(address: String) -> Result[Network, NetworkError]
```

## NetworkError {data-api-kind="Alternative"}

Errors returned by socket, DNS, and network connection operations.

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
    fn message() -> String:
```

### NetworkError.Closed

The network, listener, or socket was closed before or during the call.

```manuscript
case Closed
```

### NetworkError.Failed

Connection, bind, handshake, or DNS failure reported by the host, such as a refused connection or an unresolvable name.

```manuscript
case Failed(message: String)
```

### NetworkError.InvalidData

Text is not a valid IP address or CIDR range, or a DNS answer is not valid UTF-8.

```manuscript
case InvalidData
```

### NetworkError.InvalidInput

An address, CIDR, name, record kind, or option is malformed, or a limit or timeout is negative.

```manuscript
case InvalidInput
```

### NetworkError.LimitExceeded

A DNS lookup returned more records than `max_records`, or a received datagram is larger than `max_bytes`.

```manuscript
case LimitExceeded
```

### NetworkError.PermissionDenied

The restricted network does not allow the host, resolved address, Unix socket, or listening address.

```manuscript
case PermissionDenied
```

### NetworkError.Timeout

The supplied timeout elapsed before the operation completed.

```manuscript
case Timeout
```

### NetworkError.Unsupported

The operation is unavailable for this kind of connection, such as `shutdown_write` on a stream that cannot half-close.

```manuscript
case Unsupported
```

### NetworkError.Failed.message

Host-provided failure text; `message()` returns it verbatim, so it can name addresses.

```manuscript
message: String
```

### NetworkError.Error.message

Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `network: <reason>`.

```manuscript
fn message() -> String:
```

## contains_ip {data-api-kind="Function"}

Reports whether an IP address belongs to a CIDR range.

```manuscript
fn contains_ip(cidr: Cidr, address: IpAddress) -> Result[Bool, NetworkError]:
```

## network {data-api-kind="Function"}

Returns network operations for the current host.

```manuscript
fn network() -> Network:
```

## parse_cidr {data-api-kind="Function"}

Validates and canonicalizes an IPv4 or IPv6 CIDR range.

```manuscript
fn parse_cidr(text: String) -> Result[Cidr, NetworkError]:
```

## parse_ip {data-api-kind="Function"}

Validates and canonicalizes an IPv4 or IPv6 address.

```manuscript
fn parse_ip(text: String) -> Result[IpAddress, NetworkError]:
```

