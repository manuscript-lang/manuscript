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
    fn close() -> Unit
    # Returns this end's address as `host:port` text, with IPv6 hosts in brackets; for Unix sockets it is the socket path.
    fn local_address() -> String
    # Returns the remote end's address as `host:port` text, with IPv6 hosts in brackets.
    fn peer_address() -> String
    # Returns a positive chunk or none at EOF; local timeout uses IoError.Failed, not NetworkError.Timeout.
    fn read(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[Optional[Bytes], IoError]
    # Half-closes the connection so the peer sees end of stream, while this side can keep reading.
    # Returns Unsupported for stream kinds that cannot half-close, and Closed on a closed connection.
    fn shutdown_write() -> Result[Unit, NetworkError]
    # Returns the negotiated TLS version, cipher suite, protocol, and peer certificates.
    # A connection that is not TLS returns InvalidInput.
    fn tls_info() -> Result[TlsInfo, TlsError]
    # Writes all bytes on success; failure can leave a prefix. Local timeout uses IoError.Failed.
    fn write(data: Bytes, timeout: Optional[Duration] = none) -> Result[Unit, IoError]

# One datagram and the address from which it was received.
export type Datagram:
    # The payload bytes of this datagram, never longer than the receive call's `max_bytes`.
    data: Bytes
    # Native host:port text, with bracketed IPv6 addresses.
    sender: String

# A connectionless socket for sending and receiving datagrams.
export interface DatagramSocket:
    # Returns the bound local address as `host:port` text, which reveals the port chosen when binding port 0.
    fn address() -> String
    # Closes the socket, interrupting calls in progress, and waits for them to stop.
    # Safe to call repeatedly.
    fn close() -> Unit
    # Waits for one datagram and returns its bytes with the sender's address. `max_bytes` is 1 through 65535 and defaults to 65535.
    # A larger datagram returns LimitExceeded and is discarded. A timeout returns Timeout and a closed socket returns Closed.
    fn receive(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[Datagram, NetworkError]
    # Sends `data` as a single datagram to `address` (`host:port`), resolving a host name with the network's resolver.
    # The network's restrictions apply to both the name and the resolved address. A short send returns Failed; a timeout returns Timeout.
    fn send(
        data: Bytes,
        address: String,
        timeout: Optional[Duration] = none
    ) -> Result[Unit, NetworkError]

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
    # Returns the uppercase wire category.
    fn text() -> String:

# Numeric address families reported by IP values and host interfaces.
export type IpFamily:
    # A four-byte numeric address.
    case IPv4
    # A sixteen-byte numeric address.
    case IPv6
    # Returns IPv4 or IPv6.
    fn text() -> String:

# A validated numeric IPv4/IPv6 address without a port or zone.
export type IpAddress:
    # Returns canonical text; mapped IPv6 input is normalized to IPv4.
    fn text() -> String:
    # Returns the normalized address family.
    fn family() -> IpFamily:

# A validated, masked numeric CIDR range.
export type Cidr:
    # Returns the canonical masked prefix without reparsing.
    fn text() -> String:

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
    fn accept(timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
    # Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.
    fn address() -> String
    # Stops accepting, interrupts a pending `accept`, and waits for it to stop.
    # Safe to call repeatedly; connections already accepted stay open.
    fn close() -> Unit

# Reports whether an IP address belongs to a CIDR range.
export fn contains_ip(cidr: Cidr, address: IpAddress) -> Result[Bool, NetworkError]:

# Validates and canonicalizes an IPv4 or IPv6 CIDR range.
export fn parse_cidr(text: String) -> Result[Cidr, NetworkError]:

# Validates and canonicalizes an IPv4 or IPv6 address.
export fn parse_ip(text: String) -> Result[IpAddress, NetworkError]:

impl Error for NetworkError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `network: <reason>`.
    fn message() -> String:

# Network, DNS, HTTP, and WebSocket operations for the current host.
export interface Network:
    # Binds a UDP socket to `address` (`host:port`; port 0 picks a free port).
    # A restricted network without listening permission, or an address outside its CIDRs, returns PermissionDenied.
    fn bind_datagram(address: String) -> Result[DatagramSocket, NetworkError]
    # Cancels in-flight calls and closes every connection, listener, socket, HTTP client, and server this network opened, including those of derived networks.
    # Safe to call repeatedly. A request handler of a server on this network cannot close it and faults.
    fn close() -> Unit
    # Resolves `address` (`host:port`) and opens a TCP connection to the first reachable permitted address.
    # Returns PermissionDenied for names or addresses a restricted network disallows, Timeout when `timeout` elapses, and Failed when every address refuses.
    fn connect(
        address: String,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    # Connects over TCP to `address` and completes a TLS handshake verifying the server certificate against the system roots for `server_name`, with at least TLS 1.2.
    # An empty `server_name` returns InvalidInput, and `timeout` bounds the whole attempt.
    fn connect_tls(
        address: String,
        server_name: String,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    # Connects over TCP to `address` and completes a TLS handshake using `options`, with at least TLS 1.2.
    # Invalid options return InvalidInput, handshake and verification failures return Failed, and `timeout` bounds the whole attempt.
    fn connect_tls_config(
        address: String,
        options: TlsOptions,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    # Connects to the Unix domain socket at `path`.
    # Any restricted network returns PermissionDenied because Unix sockets bypass host and CIDR checks. `timeout` bounds the attempt.
    fn connect_unix(
        path: String,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    # Creates a reusable HTTP client with connection pooling that dials through this network, so its restrictions and resolver apply to every request and redirect.
    # Invalid or negative options return InvalidInput. Closing the network closes the client.
    fn http_client(options: HttpClientOptions) -> Result[HttpClient, HttpError]
    # Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
    # A restricted network needs `allow_listen` and an IP-literal address inside its CIDRs, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
    fn listen(address: String) -> Result[Listener, NetworkError]
    # Listens for TCP connections on `address` and completes a TLS handshake for each accepted connection, within `handshake_timeout` when supplied.
    # `options` must hold a certificate and key, otherwise InvalidInput is returned.
    fn listen_tls(
        address: String,
        options: TlsOptions,
        handshake_timeout: Optional[Duration] = none
    ) -> Result[Listener, NetworkError]
    # Listens on a Unix domain socket at `path`.
    # Any restricted network returns PermissionDenied.
    fn listen_unix(path: String) -> Result[Listener, NetworkError]
    # Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
    # More than `max_records` addresses returns LimitExceeded, `timeout` bounds the lookup, and a failed lookup returns Failed.
    fn lookup(
        name: String,
        max_records: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[List[String], NetworkError]
    # Performs one buffered HTTP request and returns the status, headers, and complete body.
    # Only `http` and `https` URLs without user info are accepted. Redirects are returned, not followed, and no cookies or proxy settings apply. A body over `max_response_bytes` returns LimitExceeded; error statuses are ordinary responses.
    fn request(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: Bytes = "".to_bytes(),
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[ClientResponse, HttpError]
    # Resolves the selected supported category, retaining it in each record.
    fn resolve(
        name: String,
        kind: DnsKind,
        max_records: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[List[DnsRecord], NetworkError]
    # Returns a derived network limited to the given host names and CIDR ranges.
    # Names match case-insensitively without a trailing dot, and IP-literal hosts also match through `cidrs`. With `cidrs`, every resolved address must be inside one of them. `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A derived restriction can only narrow its parent, and closing the parent closes the child. Invalid host or CIDR text returns InvalidInput.
    fn restrict(
        hosts: List[String],
        cidrs: List[String],
        allow_listen: Bool
    ) -> Result[Network, NetworkError]
    # Starts an HTTP server on `address` that calls `handler` with each fully buffered request and sends the returned response.
    # A request beyond `limit` concurrent requests is answered with 503, an oversized request body with 413, and a handler fault with 500. An address that cannot be bound returns IoError.Unavailable.
    fn serve(
        address: String,
        handler: fn(request: HttpRequest) -> HttpResponse,
        max_requests: Optional[Int] = none,
        max_body_bytes: Optional[Int] = none,
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none,
        grace: Optional[Duration] = none
    ) -> Result[HttpServer, IoError]
    # Starts an HTTP server on `address` whose handler receives each request as a streaming exchange. Limits, timeouts, and TLS come from `options`.
    # Returns PermissionDenied when a restricted network disallows listening, and InvalidInput for invalid options. Close the server to stop it.
    fn serve_stream(
        address: String,
        handler: fn(exchange: HttpExchange) -> Result[Unit, HttpError],
        options: HttpServerOptions
    ) -> Result[HttpServer, HttpError]
    # Opens a WebSocket client connection to a `ws` or `wss` URL, sending the given headers and offering `subprotocols` in order.
    # Handshake headers such as `Upgrade`, `Connection`, `Host`, and `Sec-WebSocket-*` cannot be set. Failures use WebSocketError.
    fn web_socket(
        url: String,
        headers: HttpHeaders,
        subprotocols: List[String],
        options: WebSocketOptions
    ) -> Result[WebSocket, WebSocketError]
    # Returns a derived network that resolves names through the DNS server at `address`, an IP literal with port, instead of the system resolver.
    # The address must be allowed by this network's restrictions, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
    fn with_resolver(address: String) -> Result[Network, NetworkError]

# Returns network operations for the current host.
export fn network() -> Network:

# documentation documentation/standard-library/network.md
# +++
# title = "Sockets and TLS"
# weight = 15
# +++
#
# # Sockets and TLS
#
# API reference: [net](reference/net.md), [tls](reference/tls.md).
#
# Use an explicit Network service to resolve names and open sockets. Connections, listeners, and datagram sockets must close when their work ends. The sections below explain destination restrictions, cancellation, and verified TLS.
#
# ## Authority and restrictions
#
# Import `network() -> Network` from `@std/net.ms` to obtain the current execution's network service. Acquired Connection, Listener and DatagramSocket views are individually imported from `@std/net.ms`, closed with `with`, and also owned by Network. Network.close stops admission, cancels and joins in-flight DNS/dials/HTTP acquisition, closes owned services and handles, and waits for admitted I/O. Concurrent close callers join the same shutdown. Repeated accessor calls return the same host root.
#
# ### Narrowing destination access
#
# Use `restrict` to create a child Network with narrower access. The child cannot grant access its parent denied. Host entries are exact DNS names, compared without case and ignoring a trailing dot. CIDR entries authorize numeric address ranges. DNS-name dialing requires the name to be allowed. If CIDRs are supplied, every chosen resolved destination must also belong to those CIDRs; raw IP dialing never bypasses a host-only restriction. Empty hosts/CIDRs deny all outbound destinations.
#
# `allow_listen` permits binding explicitly allowed numeric addresses; inbound listener peers are not an additional outbound grant. Restricted roots reject Unix socket acquisitions. Redirect hops retain the same policy. Restrictions are enforced on actual resolved addresses at dial time, not by URL string prefixes.
#
# ### Choosing a resolver
#
# `with_resolver` provisions a child with an explicit numeric DNS server address. The parent policy must authorize that server. Resolver configuration is scoped to the child; it does not mutate process-wide DNS. Lookup/resolve and UDP destination resolution use cancellable native resolver calls. Parent shutdown closes child capabilities. An unrestricted CLI root retains ordinary OS network authority; restrictions are explicit opt-in narrowing.
#
# ## DNS results
#
# `resolve(kind:)` accepts the closed DnsKind alternatives `A`, `AAAA`, `CNAME`, `MX`, `NS`, `TXT`, `PTR` and `SRV`; invalid categories fail checking. DnsRecord.kind retains the typed category, and `text()` gives its uppercase wire spelling. PTR takes a numeric address; SRV takes the full service name. CNAME returns the native canonical-name result. MX fills priority; SRV fills priority/weight/port; other numeric fields are zero. TXT joins the native record's fragments. Excess `max_records` returns an error rather than truncating. Invalid UTF-8 TXT/domain data returns InvalidData. TTL remains unrepresented because the native resolver does not expose it.
#
# `parse_ip` returns an opaque IpAddress; `parse_cidr` returns an opaque masked Cidr. Both retain `NetworkError.InvalidData` on malformed text. `text()` returns canonical numeric text without reparsing. IpAddress.family and host NetworkInterface.family use IpFamily.IPv4/IPv6. `contains_ip(cidr: Cidr, address: IpAddress)` retains `Result[Bool, NetworkError]` while checking already validated values without DNS, authority or repeated parsing. Ports remain separate native host:port text.
#
# Migration preserves the existing parse_ip policy: zones are rejected and IPv4-mapped IPv6 is normalized to IPv4. Cidr preserves its parsed family and masks host bits. Construct typed values once before repeated membership tests. A caller formerly supplying raw mapped IPv6 directly to contains_ip now passes through parse_ip's IPv4 normalization; a mapped IPv6 prefix then does not contain that canonical IPv4 value. This policy is decided: raw mapped text passed to `contains_ip` must go through `parse_ip`, so test an IPv4 block rather than a mapped IPv6 prefix for such addresses. Socket host:port/zone handling is unchanged.
#
# ## Socket lifecycle and deadlines
#
# Connect/listen addresses use native host:port notation, with IPv6 hosts in brackets (for example `[::1]:8080`) and port zero selecting an ephemeral local port on bind/listen. Datagram.sender and connection address accessors return native address text in the same notation. `parse_ip(...).text()` returns canonical numeric IPv4/IPv6 text without a port; this differs from a URL's parsed Optional[Int] port. Unix methods use native Unix-domain paths. Read and write use separate synchronization gates, allowing one of each to progress together. Calls in the same direction are serialized. Closing a handle interrupts blocking I/O and waits for admitted operations. Metadata remains readable after close. A half-close ends writing while leaving reads available. It is supported for TCP, Unix, and TLS connections. Read follows the existing IoError/Optional Bytes contract: positive bounded chunks, none for EOF, and Closed for stale aliases. Writes accept all bytes or return an error after a possible external prefix.
#
# ### Accept and handshake cancellation
#
# Listener accept cancellation uses an interruptible deadline and restores it before releasing the accept gate. Cancellation and accept do not destroy the listener: it can admit another accept afterwards. A TLS listener applies its optional handshake deadline; shutdown cancels admitted handshakes. Accepted handles retain Network ownership. Unix socket availability follows the target OS, not a separate deferred API.
#
# ### Datagrams and operation timeouts
#
# UDP preserves message boundaries, including empty messages. Receive accepts max_bytes 1–65535 and returns LimitExceeded on an oversized consumed packet, never a truncated success. UDP name resolution responds to caller cancellation and Network/socket closure. The ordinary operations accept optional nonnegative timeouts: zero is an immediate deadline, and omission adds no deadline. Expected local timeouts return NetworkError.Timeout; Connection operations retain IoError and use Failed with a timeout diagnostic. Parent cancellation always unwinds. Operation deadlines are cleared under the direction gate before the next operation starts.
#
# ## TLS and certificates
#
# TLS supports 1.2 and newer with native authenticated ciphers. connect_tls uses system trust plus a required server_name; connect_tls_config accepts explicit trust PEM, client certificate/key, and ALPN. listen_tls uses a server certificate/key and can require verified client certificates. Empty roots select system trust for clients; supplied roots replace that client trust store. There is no insecure-skip-verification switch or retry. Configured names are checked against certificates; chain validation and expiration remain enabled. ALPN values must be nonempty protocol tokens of at most 255 bytes.
#
# ### Hostnames and certificate helpers
#
# HTTP/WebSocket clients validate each URL hostname; the generic client TLS server_name field does not override subsequent origins. Private-key PEM is explicit input, not an imported ambient secret. Parse_certificates validates PEM/DER syntax with a certificate count bound and exposes metadata. Verify_certificates takes an explicit PEM chain, trust roots, a nonempty name and Timestamp for pure deterministic chain/hostname/expiry validation. Tls_info exposes negotiated version/cipher/ALPN and peer DER certificates, without exposing private keys.
#
# See [HTTP](http.md) for HTTP/1.1 and HTTP/2, and [WebSockets](websocket.md) for message sessions.
# end-documentation
