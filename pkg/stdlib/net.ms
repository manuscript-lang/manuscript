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
import HttpHeaders from "@std/http.ms"
import HttpMethod from "@std/http.ms"
import Bytes from "@std/bytes.ms"
import Duration from "@std/time.ms"
import IoError from "@std/io.ms"
import TlsError from "@std/tls.ms"
import TlsInfo from "@std/tls.ms"

# Errors returned by socket, DNS, and network connection operations.
export type NetworkError:
    # An address, CIDR, name, record kind, or option is malformed, or a limit or timeout is negative.
    case InvalidInput
    # Text is not a valid IP address or CIDR range, or a DNS answer is not valid UTF-8.
    case InvalidData
    # A DNS lookup returned more records than `max_records`, or a received datagram is larger than `max_bytes`.
    case LimitExceeded
    # The restricted network does not allow the host, resolved address, Unix socket, or listening address.
    case PermissionDenied
    # The operation is unavailable for this kind of connection, such as `shutdown_write` on a stream that cannot half-close.
    case Unsupported
    # The network, listener, or socket was closed before or during the call.
    case Closed
    # The supplied timeout elapsed before the operation completed.
    case Timeout
    # Connection, bind, handshake, or DNS failure reported by the host, such as a refused connection or an unresolvable name.
    case Failed(
        # Host-provided failure text; `message()` returns it verbatim, so it can name addresses.
        message: String
    )

# A connected stream socket, optionally protected by TLS.
export interface Connection:
    # Closes the socket, interrupting calls in progress, and waits for them to stop.
    # Safe to call repeatedly; later calls wait for the first. Reads and writes afterwards return Closed.
    fn close() Unit
    # Returns this end's address as `host:port` text, with IPv6 hosts in brackets; for Unix sockets it is the socket path.
    fn local_address() String
    # Returns the remote end's address as `host:port` text, with IPv6 hosts in brackets.
    fn peer_address() String
    # Returns a positive chunk or none at EOF; local timeout uses IoError.Failed, not NetworkError.Timeout.
    fn read(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) Result[Optional[Bytes], IoError]
    # Half-closes the connection so the peer sees end of stream, while this side can keep reading.
    # Returns Unsupported for stream kinds that cannot half-close, and Closed on a closed connection.
    fn shutdown_write() Result[Unit, NetworkError]
    # Returns the negotiated TLS version, cipher suite, protocol, and peer certificates.
    # A connection that is not TLS returns InvalidInput.
    fn tls_info() Result[TlsInfo, TlsError]
    # Writes all bytes on success; failure can leave a prefix. Local timeout uses IoError.Failed.
    fn write(data: Bytes, timeout: Optional[Duration] = none) Result[Unit, IoError]

# One datagram and the address from which it was received.
export type Datagram:
    # The payload bytes of this datagram, never longer than the receive call's `max_bytes`.
    data: Bytes
    # Native host:port text, with bracketed IPv6 addresses.
    sender: String

# A connectionless socket for sending and receiving datagrams.
export interface DatagramSocket:
    # Returns the bound local address as `host:port` text, which reveals the port chosen when binding port 0.
    fn address() String
    # Closes the socket, interrupting calls in progress, and waits for them to stop.
    # Safe to call repeatedly.
    fn close() Unit
    # Waits for one datagram and returns its bytes with the sender's address. `max_bytes` is 1 through 65535 and defaults to 65535.
    # A larger datagram returns LimitExceeded and is discarded. A timeout returns Timeout and a closed socket returns Closed.
    fn receive(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) Result[Datagram, NetworkError]
    # Sends `data` as a single datagram to `address` (`host:port`), resolving a host name with the network's resolver.
    # The network's restrictions apply to both the name and the resolved address. A short send returns Failed; a timeout returns Timeout.
    fn send(
        data: Bytes,
        address: String,
        timeout: Optional[Duration] = none
    ) Result[Unit, NetworkError]

# Supported DNS query categories; unknown spellings are rejected by checking.
export type DnsKind:
    # IPv4 address records for the queried name.
    case A
    # IPv6 address records for the queried name.
    case AAAA
    # Canonical name alias records for the queried name.
    case CNAME
    # Mail exchange records with priority values.
    case MX
    # Name server records for the queried zone.
    case NS
    # Text records returned as string values.
    case TXT
    # Reverse address pointer records for an IP.
    case PTR
    # Service location records with priority, weight and port.
    case SRV

impl DnsKind:
    # Returns the uppercase wire category.
    fn text() String:

# Numeric address families reported by IP values and host interfaces.
export type IpFamily:
    # A four-byte numeric address.
    case IPv4
    # A sixteen-byte numeric address.
    case IPv6

impl IpFamily:
    # Returns IPv4 or IPv6.
    fn text() String:

# A validated numeric IPv4/IPv6 address without a port or zone.
export type IpAddress:

impl IpAddress:
    # Returns canonical text; mapped IPv6 input is normalized to IPv4.
    fn text() String:

    # Returns the normalized address family.
    fn family() IpFamily:

# A validated, masked numeric CIDR range.
export type Cidr:

impl Cidr:
    # Returns the canonical masked prefix without reparsing.
    fn text() String:

# DNS record data returned by a typed lookup.
export type DnsRecord:
    # The same typed category used by the query.
    kind: DnsKind
    # The record's answer: an IP address for A and AAAA, the target host name for CNAME, MX, NS, PTR, and SRV, or the text for TXT.
    value: String
    # The preference of an MX record or the priority of an SRV record, where lower values are tried first; 0 for other kinds.
    priority: Int
    # The relative weight of an SRV record among targets with the same priority; 0 for other kinds.
    weight: Int
    # The service port of an SRV record; 0 for other kinds.
    port: Int

# A listening socket that accepts incoming connections.
export interface Listener:
    # Waits for the next incoming connection and returns it. A timeout returns Timeout and a closed listener returns Closed.
    # On a TLS listener the handshake completes before the connection is returned; a failed handshake drops that connection and returns Failed.
    fn accept(timeout: Optional[Duration] = none) Result[Connection, NetworkError]
    # Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.
    fn address() String
    # Stops accepting, interrupts a pending `accept`, and waits for it to stop.
    # Safe to call repeatedly; connections already accepted stay open.
    fn close() Unit

# Reports whether an IP address belongs to a CIDR range.
export fn contains_ip(cidr: Cidr, address: IpAddress) Result[Bool, NetworkError]:

# Validates and canonicalizes an IPv4 or IPv6 CIDR range.
export fn parse_cidr(text: String) Result[Cidr, NetworkError]:

# Validates and canonicalizes an IPv4 or IPv6 address.
export fn parse_ip(text: String) Result[IpAddress, NetworkError]:

impl Error for NetworkError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `network: <reason>`.
    fn message() String:

# Network, DNS, HTTP, and WebSocket operations for the current host.
export interface Network:
    # Binds a UDP socket to `address` (`host:port`; port 0 picks a free port).
    # A restricted network without listening permission, or an address outside its CIDRs, returns PermissionDenied.
    fn bind_datagram(address: String) Result[DatagramSocket, NetworkError]
    # Cancels in-flight calls and closes every connection, listener, socket, HTTP client, and server this network opened, including those of derived networks.
    # Safe to call repeatedly. A request handler of a server on this network cannot close it and faults.
    fn close() Unit
    # Resolves `address` (`host:port`) and opens a TCP connection to the first reachable permitted address.
    # Returns PermissionDenied for names or addresses a restricted network disallows, Timeout when `timeout` elapses, and Failed when every address refuses.
    fn connect(
        address: String,
        timeout: Optional[Duration] = none
    ) Result[Connection, NetworkError]
    # Connects over TCP to `address` and completes a TLS handshake verifying the server certificate against the system roots for `server_name`, with at least TLS 1.2.
    # An empty `server_name` returns InvalidInput, and `timeout` bounds the whole attempt.
    fn connect_tls(
        address: String,
        server_name: String,
        timeout: Optional[Duration] = none
    ) Result[Connection, NetworkError]
    # Connects over TCP to `address` and completes a TLS handshake using `options`, with at least TLS 1.2.
    # Invalid options return InvalidInput, handshake and verification failures return Failed, and `timeout` bounds the whole attempt.
    fn connect_tls_config(
        address: String,
        options: TlsOptions,
        timeout: Optional[Duration] = none
    ) Result[Connection, NetworkError]
    # Connects to the Unix domain socket at `path`.
    # Any restricted network returns PermissionDenied because Unix sockets bypass host and CIDR checks. `timeout` bounds the attempt.
    fn connect_unix(
        path: String,
        timeout: Optional[Duration] = none
    ) Result[Connection, NetworkError]
    # Creates a reusable HTTP client with connection pooling that dials through this network, so its restrictions and resolver apply to every request and redirect.
    # Invalid or negative options return InvalidInput. Closing the network closes the client.
    fn http_client(options: HttpClientOptions) Result[HttpClient, HttpError]
    # Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
    # A restricted network needs `allow_listen` and an IP-literal address inside its CIDRs, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
    fn listen(address: String) Result[Listener, NetworkError]
    # Listens for TCP connections on `address` and completes a TLS handshake for each accepted connection, within `handshake_timeout` when supplied.
    # `options` must hold a certificate and key, otherwise InvalidInput is returned.
    fn listen_tls(
        address: String,
        options: TlsOptions,
        handshake_timeout: Optional[Duration] = none
    ) Result[Listener, NetworkError]
    # Listens on a Unix domain socket at `path`.
    # Any restricted network returns PermissionDenied.
    fn listen_unix(path: String) Result[Listener, NetworkError]
    # Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
    # More than `max_records` addresses returns LimitExceeded, `timeout` bounds the lookup, and a failed lookup returns Failed.
    fn lookup(
        name: String,
        max_records: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) Result[List[String], NetworkError]
    # Performs one buffered HTTP request and returns the status, headers, and complete body.
    # Only `http` and `https` URLs without user info are accepted. Redirects are returned, not followed, and no cookies or proxy settings apply. A body over `max_response_bytes` returns LimitExceeded; error statuses are ordinary responses.
    fn request(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: Bytes = "".to_bytes(),
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) Result[ClientResponse, HttpError]
    # Resolves the selected supported category, retaining it in each record.
    fn resolve(
        name: String,
        kind: DnsKind,
        max_records: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) Result[List[DnsRecord], NetworkError]
    # Returns a derived network limited to the given host names and CIDR ranges.
    # Names match case-insensitively without a trailing dot, and IP-literal hosts also match through `cidrs`. With `cidrs`, every resolved address must be inside one of them. `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A derived restriction can only narrow its parent, and closing the parent closes the child. Invalid host or CIDR text returns InvalidInput.
    fn restrict(
        hosts: List[String],
        cidrs: List[String],
        allow_listen: Bool
    ) Result[Network, NetworkError]
    # Starts an HTTP server on `address` that calls `handler` with each fully buffered request and sends the returned response.
    # A request beyond `limit` concurrent requests is answered with 503, an oversized request body with 413, and a handler fault with 500. An address that cannot be bound returns IoError.Unavailable.
    fn serve(
        address: String,
        handler: fn(request: HttpRequest) HttpResponse,
        max_requests: Optional[Int] = none,
        max_body_bytes: Optional[Int] = none,
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none,
        grace: Optional[Duration] = none
    ) Result[HttpServer, IoError]
    # Starts an HTTP server on `address` whose handler receives each request as a streaming exchange. Limits, timeouts, and TLS come from `options`.
    # Returns PermissionDenied when a restricted network disallows listening, and InvalidInput for invalid options. Close the server to stop it.
    fn serve_stream(
        address: String,
        handler: fn(exchange: HttpExchange) Result[Unit, HttpError],
        options: HttpServerOptions
    ) Result[HttpServer, HttpError]
    # Opens a WebSocket client connection to a `ws` or `wss` URL, sending the given headers and offering `subprotocols` in order.
    # Handshake headers such as `Upgrade`, `Connection`, `Host`, and `Sec-WebSocket-*` cannot be set. Failures use WebSocketError.
    fn web_socket(
        url: String,
        headers: HttpHeaders,
        subprotocols: List[String],
        options: WebSocketOptions
    ) Result[WebSocket, WebSocketError]
    # Returns a derived network that resolves names through the DNS server at `address`, an IP literal with port, instead of the system resolver.
    # The address must be allowed by this network's restrictions, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
    fn with_resolver(address: String) Result[Network, NetworkError]

# Returns network operations for the current host.
export fn network() Network:
