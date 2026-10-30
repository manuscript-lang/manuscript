import Closeable, Data from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import ClientResponse from "@std/http.ms"
import Duration from "@std/time.ms"
import HttpClient from "@std/http.ms"
import HttpClientOptions from "@std/http.ms"
import HttpError from "@std/http.ms"
import HttpExchange from "@std/http.ms"
import HttpHeaders from "@std/http.ms"
import HttpMethod from "@std/http.ms"
import HttpServer from "@std/http.ms"
import HttpServerOptions from "@std/http.ms"
import IoError from "@std/io.ms"
import Timestamp from "@std/time.ms"
import WorkerGroup, worker_channel from "@std/workers.ms"

extern fn msrt_net_ip_address_text(value: IpAddress) String

extern fn msrt_net_ip_address_family(value: IpAddress) Bool

extern fn msrt_net_cidr_text(value: Cidr) String

extern fn msrt_net_contains_ip(
    cidr: Cidr,
    address: IpAddress
) Result[Bool, NetworkError]

extern fn msrt_net_parse_cidr(text: String) Result[Cidr, NetworkError]

extern fn msrt_net_parse_ip(text: String) Result[IpAddress, NetworkError]

extern fn msrt_net_network() Network

extern fn msrt_tls_parse_certificates(
    pem: String,
    max_certificates: Optional[Int]
) Result[List[CertificateInfo], TlsError]

extern fn msrt_tls_verify_certificates(
    chain_pem: String,
    roots_pem: String,
    server_name: String,
    now: Timestamp
) Result[Unit, TlsError]

extern fn msrt_url_decode_component(text: String) Result[String, UrlError]

extern fn msrt_url_encode_component(text: String) String

extern fn msrt_url_format(value: Url) Result[String, UrlError]

extern fn msrt_url_format_query(entries: List[QueryEntry]) String

extern fn msrt_url_parse(text: String) Result[Url, UrlError]

extern fn msrt_url_parse_query(
    text: String,
    max_entries: Optional[Int]
) Result[List[QueryEntry], UrlError]

extern fn msrt_url_resolve(base: Url, reference: String) Result[Url, UrlError]

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

# The runtime handle behind a `Connection`.
export extern type NativeConnection

extern fn msrt_net_connection_close(handle: NativeConnection) Unit

extern fn msrt_net_connection_local_address(handle: NativeConnection) String

extern fn msrt_net_connection_peer_address(handle: NativeConnection) String

extern fn msrt_net_connection_read(
    handle: NativeConnection,
    max_bytes: Optional[Int],
    timeout: Optional[Duration]
) Result[Optional[Bytes], IoError]

extern fn msrt_net_connection_shutdown_write(
    handle: NativeConnection
) Result[Unit, NetworkError]

extern fn msrt_net_connection_tls_info(
    handle: NativeConnection
) Result[TlsInfo, TlsError]

extern fn msrt_net_connection_write(
    handle: NativeConnection,
    data: String,
    timeout: Optional[Duration]
) Result[Unit, IoError]

extern fn msrt_net_connection_write_bytes(
    handle: NativeConnection,
    data: Bytes,
    timeout: Optional[Duration]
) Result[Unit, IoError]

# A connected stream socket, optionally protected by TLS.
# Several tasks may wait on one connection: each `read` parks until data arrives, and tasks are woken together, so the one that finds data proceeds and the rest wait again. Writers sharing a connection should serialize whole messages themselves.
export type Connection:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeConnection

impl Closeable for Connection:
    # Closes the socket, interrupting calls in progress, and waits for them to stop.
    # Safe to call repeatedly; later calls wait for the first. Reads and writes afterwards return Closed.
    var fn close() Unit:
        msrt_net_connection_close(self.native)

impl Connection:
    # Returns this end's address as `host:port` text, with IPv6 hosts in brackets; for Unix sockets it is the socket path.
    fn local_address() String:
        return msrt_net_connection_local_address(self.native)

    # Returns the remote end's address as `host:port` text, with IPv6 hosts in brackets.
    fn peer_address() String:
        return msrt_net_connection_peer_address(self.native)

    # Returns a positive chunk or none at EOF; local timeout uses IoError.Failed, not NetworkError.Timeout.
    fn read(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) Result[Optional[Bytes], IoError]:
        return msrt_net_connection_read(self.native, max_bytes, timeout)

    # Half-closes the connection so the peer sees end of stream, while this side can keep reading.
    # Returns Unsupported for stream kinds that cannot half-close, and Closed on a closed connection.
    fn shutdown_write() Result[Unit, NetworkError]:
        return msrt_net_connection_shutdown_write(self.native)

    # Returns the negotiated TLS version, cipher suite, protocol, and peer certificates.
    # A connection that is not TLS returns InvalidInput.
    fn tls_info() Result[TlsInfo, TlsError]:
        return msrt_net_connection_tls_info(self.native)

    # Writes all bytes on success; failure can leave a prefix. Local timeout uses IoError.Failed.
    fn write(data: String, timeout: Optional[Duration] = none) Result[Unit, IoError]:
        return msrt_net_connection_write(self.native, data, timeout)

    # Writes raw bytes with the same rules as write.
    fn write_bytes(
        data: Bytes,
        timeout: Optional[Duration] = none
    ) Result[Unit, IoError]:
        return msrt_net_connection_write_bytes(self.native, data, timeout)

# One datagram and the address from which it was received.
export type Datagram:
    # The payload bytes of this datagram, never longer than the receive call's `max_bytes`.
    data: Bytes
    # Native host:port text, with bracketed IPv6 addresses.
    sender: String

# The runtime handle behind a `DatagramSocket`.
export extern type NativeDatagramSocket

extern fn msrt_net_datagram_address(handle: NativeDatagramSocket) String

extern fn msrt_net_datagram_close(handle: NativeDatagramSocket) Unit

extern fn msrt_net_datagram_receive(
    handle: NativeDatagramSocket,
    max_bytes: Optional[Int],
    timeout: Optional[Duration]
) Result[Datagram, NetworkError]

extern fn msrt_net_datagram_send(
    handle: NativeDatagramSocket,
    data: String,
    address: String,
    timeout: Optional[Duration]
) Result[Unit, NetworkError]

extern fn msrt_net_datagram_send_bytes(
    handle: NativeDatagramSocket,
    data: Bytes,
    address: String,
    timeout: Optional[Duration]
) Result[Unit, NetworkError]

# A connectionless socket for sending and receiving datagrams.
export type DatagramSocket:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeDatagramSocket

impl Closeable for DatagramSocket:
    # Closes the socket, interrupting calls in progress, and waits for them to stop.
    # Safe to call repeatedly.
    var fn close() Unit:
        msrt_net_datagram_close(self.native)

impl DatagramSocket:
    # Returns the bound local address as `host:port` text, which reveals the port chosen when binding port 0.
    fn address() String:
        return msrt_net_datagram_address(self.native)

    # Waits for one datagram and returns its bytes with the sender's address. `max_bytes` is 1 through 65535 and defaults to 65535.
    # A larger datagram returns LimitExceeded and is discarded. A timeout returns Timeout and a closed socket returns Closed.
    fn receive(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) Result[Datagram, NetworkError]:
        return msrt_net_datagram_receive(self.native, max_bytes, timeout)

    # Sends `data` as a single datagram to `address` (`host:port`), resolving a host name with the network's resolver.
    # The network's restrictions apply to both the name and the resolved address. A short send returns Failed; a timeout returns Timeout.
    fn send(
        data: String,
        address: String,
        timeout: Optional[Duration] = none
    ) Result[Unit, NetworkError]:
        return msrt_net_datagram_send(self.native, data, address, timeout)

    # Sends raw bytes as a single datagram with the same rules as send.
    fn send_bytes(
        data: Bytes,
        address: String,
        timeout: Optional[Duration] = none
    ) Result[Unit, NetworkError]:
        return msrt_net_datagram_send_bytes(self.native, data, address, timeout)

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
        match self:
            A: return "A"
            AAAA: return "AAAA"
            CNAME: return "CNAME"
            MX: return "MX"
            NS: return "NS"
            TXT: return "TXT"
            PTR: return "PTR"
            SRV: return "SRV"

# Numeric address families reported by IP values and host interfaces.
export type IpFamily:
    # A four-byte numeric address.
    case IPv4
    # A sixteen-byte numeric address.
    case IPv6

impl IpFamily:
    # Returns IPv4 or IPv6.
    fn text() String:
        match self:
            IPv4: return "IPv4"
            IPv6: return "IPv6"

# A validated numeric IPv4/IPv6 address without a port or zone.
export extern type IpAddress

impl Data for IpAddress:

impl IpAddress:
    # Returns canonical text; mapped IPv6 input is normalized to IPv4.
    fn text() String:
        return msrt_net_ip_address_text(self)

    # Returns the normalized address family.
    fn family() IpFamily:
        if msrt_net_ip_address_family(self):
            return IPv6

        return IPv4

# A validated, masked numeric CIDR range.
export extern type Cidr

impl Data for Cidr:

impl Cidr:
    # Returns the canonical masked prefix without reparsing.
    fn text() String:
        return msrt_net_cidr_text(self)

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

# The runtime handle behind a `Listener`.
export extern type NativeListener

extern fn msrt_net_listener_accept(
    handle: NativeListener,
    timeout: Optional[Duration]
) Result[Connection, NetworkError]

extern fn msrt_net_listener_accept_raw(
    handle: NativeListener,
    timeout: Optional[Duration]
) Result[Int, NetworkError]

extern fn msrt_net_listener_address(handle: NativeListener) String

extern fn msrt_net_listener_close(handle: NativeListener) Unit

# A listening socket that accepts incoming connections.
# Several tasks may call `accept` on one listener (an accept pool); each incoming connection goes to exactly one of them.
export type Listener:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeListener

impl Closeable for Listener:
    # Stops accepting, interrupts a pending `accept`, and waits for it to stop.
    # Safe to call repeatedly; connections already accepted stay open.
    var fn close() Unit:
        msrt_net_listener_close(self.native)

impl Listener:
    # Waits for the next incoming connection and returns it. A timeout returns Timeout and a closed listener returns Closed.
    # On a TLS listener the handshake completes before the connection is returned; a failed handshake drops that connection and returns Failed.
    fn accept(timeout: Optional[Duration] = none) Result[Connection, NetworkError]:
        return msrt_net_listener_accept(self.native, timeout)

    # Waits for the next incoming connection and returns its socket handle without wrapping it, to give to `HttpServer.adopt` (on this or another thread). The caller owns the handle until then; one that is never adopted leaks its socket.
    # A timeout returns Timeout and a closed listener returns Closed. A TLS listener returns InvalidInput: the adopting server performs the handshake.
    fn accept_raw(timeout: Optional[Duration] = none) Result[Int, NetworkError]:
        return msrt_net_listener_accept_raw(self.native, timeout)

    # Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.
    fn address() String:
        return msrt_net_listener_address(self.native)

# Reports whether an IP address belongs to a CIDR range.
export fn contains_ip(cidr: Cidr, address: IpAddress) Result[Bool, NetworkError]:
    return msrt_net_contains_ip(cidr, address)

# Validates and canonicalizes an IPv4 or IPv6 CIDR range.
export fn parse_cidr(text: String) Result[Cidr, NetworkError]:
    return msrt_net_parse_cidr(text)

# Validates and canonicalizes an IPv4 or IPv6 address.
export fn parse_ip(text: String) Result[IpAddress, NetworkError]:
    return msrt_net_parse_ip(text)

impl Error for NetworkError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `network: <reason>`.
    fn message() String:
        match self:
            InvalidInput: return "network: invalid input"
            InvalidData: return "network: invalid data"
            LimitExceeded: return "network: limit exceeded"
            PermissionDenied: return "network: permission denied"
            Unsupported: return "network: operation not supported"
            Closed: return "network: resource is closed"
            Timeout: return "network: operation timed out"
            Failed(message): return message.clone()

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
    # System-resolver lookups run on the runtime's blocking threads (`MS_POOL_THREADS`, default 4), at most half of them at once, while other tasks keep running.
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
        body: String = "",
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) Result[ClientResponse, HttpError]
    # Performs the same buffered request with a raw bytes body.
    fn request_bytes(
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
    # Starts an HTTP server on `address` whose handler receives each request as an exchange: read the body and write the response incrementally, or use `read_body`, `reply`, and `buffered` from `@std/http.ms` for whole messages. Limits, timeouts, and TLS come from `options`.
    # A request beyond `max_requests` concurrent requests is answered with 503, an oversized header block with 431, and a handler fault with 500. An address that cannot be bound returns Failed.
    # Returns PermissionDenied when a restricted network disallows listening, and InvalidInput for invalid options. Close the server to stop it.
    # A handler is cancelled when its request times out or its client disconnects (an HTTP/1 connection closes or an HTTP/2 stream is reset): its waits end, `tasks.cancelled()` turns true, and its cleanups run. A client that half-closes its end after sending the request counts as disconnected.
    # A faulting handler's frames release the heap values they own, as a cancelled handler's do. Return an error response for expected failures instead of faulting.
    fn serve(
        address: String,
        handler: fn(HttpExchange) Result[Unit, HttpError],
        options: HttpServerOptions = HttpServerOptions()
    ) Result[HttpServer, HttpError]
    # Opens a WebSocket client connection to a `ws` or `wss` URL, sending the given headers and offering `subprotocols` in order.
    # Handshake headers such as `Upgrade`, `Connection`, `Host`, and `Sec-WebSocket-*` cannot be set. Failures use WebSocketError.
    fn web_socket(
        url: String,
        headers: HttpHeaders,
        subprotocols: List[String],
        options: WebSocketOptions
    ) Result[WebSocket, WebSocketError]
    # Starts an HTTP server that has no listener: it serves the connections handed to `HttpServer.adopt`, with the handler, limits, timeouts, and TLS of `serve`. Close the server to stop it.
    # Returns InvalidInput for invalid options.
    fn serve_connections(
        handler: fn(HttpExchange) Result[Unit, HttpError],
        options: HttpServerOptions = HttpServerOptions()
    ) Result[HttpServer, HttpError]
    # Returns a derived network that resolves names through the DNS server at `address`, an IP literal with port, instead of the system resolver.
    # The address must be allowed by this network's restrictions, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
    fn with_resolver(address: String) Result[Network, NetworkError]

# Returns network operations for the current host.
export fn network() Network:
    return msrt_net_network()

# Errors returned when TLS configuration, certificates, or peer authentication fail.
export type TlsError:
    # A certificate limit is negative, a `server_name` is empty, or `tls_info` was requested on a connection that is not TLS.
    case InvalidInput
    # The PEM text is not a sequence of well-formed CERTIFICATE blocks, or a chain or roots argument holds no certificate.
    case InvalidData
    # The PEM text holds more certificates than `max_certificates`.
    case LimitExceeded
    # Chain verification failed: the chain does not lead to a supplied root, a certificate is expired or not yet valid at the supplied time, or the name does not match.
    case AuthenticationFailed

# Parsed certificate identity, validity range, and original DER bytes.
export type CertificateInfo:
    # The certificate subject as a distinguished-name string, such as `CN=example.com,O=Example`.
    subject: String
    # The issuing authority as a distinguished-name string, in the same format as `subject`.
    issuer: String
    # DNS subject alternative names in certificate order; empty when the certificate has none.
    dns_names: List[String]
    # Start of the validity period as a UTC Timestamp.
    not_before: Timestamp
    # End of the validity period as a UTC Timestamp.
    not_after: Timestamp
    # The certificate's binary DER encoding, as a copy independent of the PEM text.
    der: Bytes

# Negotiated TLS version, cipher, protocol, and peer certificate information.
export type TlsInfo:
    # Negotiated protocol version as its numeric wire code, such as 771 (0x0303) for TLS 1.2 or 772 (0x0304) for TLS 1.3.
    version: Int
    # Negotiated cipher suite as its numeric IANA identifier, such as 4865 (0x1301) for TLS_AES_128_GCM_SHA256.
    cipher_suite: Int
    # The application protocol both sides agreed on, or an empty string when none was negotiated.
    alpn: String
    # The peer's presented certificates as DER bytes, leaf first; empty when the peer sent none.
    peer_certificates: List[Bytes]
    # True when the peer's certificate chain was verified against the configured roots; False when no peer chain was verified.
    verified: Bool

# Client or server TLS settings, including roots, certificates, and ALPN protocols.
export type TlsOptions:
    # Host name a TLS client sends for server name indication and matches against the server certificate; it must be non-empty for `connect_tls_config`.
    # HTTP and WebSocket clients take the name from the URL host and ignore this field, and servers do not use it.
    server_name: String
    # PEM certificates to trust. Clients use them instead of the system roots; servers use them to verify client certificates. An empty string selects the system roots; invalid PEM is rejected.
    roots_pem: String
    # PEM certificate chain this side presents, paired with `private_key_pem`. Servers must supply it; clients supply it only for mutual TLS.
    certificate_pem: String
    # PEM private key matching `certificate_pem`. Both must be set together and match, or setup fails.
    private_key_pem: String
    # Application-layer protocols to offer or accept, in preference order, such as `h2` or `http/1.1`. Each must be 1 through 255 bytes; empty disables negotiation.
    alpn: List[String]
    # Servers only: when True, a client must present a certificate that verifies against `roots_pem`. Setting it on a client configuration is rejected.
    require_client_certificate: Bool

# Parses PEM certificates and optionally limits the number returned.
export fn parse_certificates(
    pem: String,
    max_certificates: Optional[Int] = none
) Result[List[CertificateInfo], TlsError]:
    return msrt_tls_parse_certificates(pem, max_certificates)

# Verifies a PEM certificate chain against roots, name constraints, and the supplied time.
export fn verify_certificates(
    chain_pem: String,
    roots_pem: String,
    server_name: String,
    now: Timestamp
) Result[Unit, TlsError]:
    return msrt_tls_verify_certificates(chain_pem, roots_pem, server_name, now)

impl Error for TlsError:
    # Returns the fixed diagnostic `TLS: <reason>`, such as `TLS: authentication failed`, without echoing certificate text.
    fn message() String:
        match self:
            InvalidInput: return "TLS: invalid input"
            InvalidData: return "TLS: invalid data"
            LimitExceeded: return "TLS: limit exceeded"
            AuthenticationFailed: return "TLS: authentication failed"

# Errors returned for malformed URL text, components, or query limits.
export type UrlError:
    # Constructed URL components or a supplied query-entry budget are invalid.
    case InvalidInput
    # URL text, escaped bytes, port syntax or a relative reference is invalid or unsupported.
    case InvalidData
    # The decoded query has more entries than its supplied budget permits.
    case LimitExceeded

# One decoded key and value in a URL query string.
export type QueryEntry:
    # Decoded query key; duplicate keys retain separate entries in input order.
    key: String
    # Decoded query value; a bare key has an empty value and plus decodes as a space.
    value: String

# Parsed URL components. A missing port is represented by `none`.
export type Url:
    # URL scheme, lowercased during parsing; native parse rejects missing schemes and opaque URLs.
    scheme: String
    # Lowercased hostname, excluding the port and IPv6 brackets; user information is rejected.
    host: String
    # Explicit numeric port in 0..65535, or none when the input has no port.
    port: Optional[Int]
    # Escaped path text, retaining escaped separators; format validates its percent escapes and UTF-8.
    path: String
    # Encoded query contents without the leading question mark; parse_query decodes individual entries.
    query: String
    # Decoded fragment contents without the leading hash mark.
    fragment: String

# Decodes one percent-encoded URL component. `+` is not treated as a space.
export fn decode_component(text: String) Result[String, UrlError]:
    return msrt_url_decode_component(text)

# Percent-encodes one URL component using UTF-8 bytes.
export fn encode_component(text: String) String:
    return msrt_url_encode_component(text)

# Formats URL components as an absolute hierarchical URL.
# Missing or malformed schemes and hostless relative paths return InvalidInput, as do other invalid components.
export fn format(value: Url) Result[String, UrlError]:
    return msrt_url_format(value)

# Encodes query entries as a query string.
export fn format_query(entries: List[QueryEntry]) String:
    return msrt_url_format_query(entries)

# Parses an absolute URL into its components.
export fn parse(text: String) Result[Url, UrlError]:
    return msrt_url_parse(text)

# Parses a query string, preserving duplicate keys and their input order.
export fn parse_query(
    text: String,
    max_entries: Optional[Int] = none
) Result[List[QueryEntry], UrlError]:
    return msrt_url_parse_query(text, max_entries)

# Resolves a relative reference against a base URL.
export fn resolve(base: Url, reference: String) Result[Url, UrlError]:
    return msrt_url_resolve(base, reference)

impl Error for UrlError:
    # Returns a URL-prefixed diagnostic without echoing addresses, query values or credentials.
    fn message() String:
        match self:
            InvalidInput: return "URL: invalid input"
            InvalidData: return "URL: invalid data"
            LimitExceeded: return "URL: limit exceeded"

# Errors returned by WebSocket handshakes, message limits, timeouts, or closed sockets.
export type WebSocketError:
    # A URL is not a `ws` or `wss` URL with a host and no user info, `max_message_bytes` is not positive, a header, subprotocol, or option is malformed, or a ping payload exceeds 125 bytes.
    case InvalidInput
    # A text message is not valid UTF-8, whether being sent or received.
    case InvalidData
    # A message is larger than `max_message_bytes`.
    case LimitExceeded
    # The network handle's restriction policy does not allow the host.
    case PermissionDenied
    # The socket or its network handle was closed, or an earlier read failure already ended the connection.
    case Closed
    # The connection attempt did not finish within `timeout`.
    case Timeout
    # Handshake, transport, or protocol failure, such as a refused connection or a rejected upgrade.
    case Failed(
        # Host-provided failure text; `message()` returns it verbatim, so it can name addresses.
        message: String
    )

# The runtime handle behind a `WebSocket`.
export extern type NativeWebSocket

extern fn msrt_websocket_close(handle: NativeWebSocket) Unit

extern fn msrt_websocket_ping(
    handle: NativeWebSocket,
    data: String
) Result[Unit, WebSocketError]

extern fn msrt_websocket_ping_bytes(
    handle: NativeWebSocket,
    data: Bytes
) Result[Unit, WebSocketError]

extern fn msrt_websocket_receive(
    handle: NativeWebSocket
) Result[Optional[WebSocketMessage], WebSocketError]

extern fn msrt_websocket_send(
    handle: NativeWebSocket,
    data: String
) Result[Unit, WebSocketError]

extern fn msrt_websocket_send_bytes(
    handle: NativeWebSocket,
    data: Bytes,
    text: Bool
) Result[Unit, WebSocketError]

extern fn msrt_websocket_subprotocol(handle: NativeWebSocket) String

# A WebSocket connection. Send and receive byte messages with an explicit text flag.
export type WebSocket:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeWebSocket

impl Closeable for WebSocket:
    # Sends a normal-closure frame, waiting at most about 100 ms to write it, then closes the connection and waits for in-flight calls to stop.
    # Safe to call repeatedly; later calls wait for the first.
    var fn close() Unit:
        msrt_websocket_close(self.native)

impl WebSocket:
    # Sends a ping frame carrying `data`, which must be at most 125 bytes, with a one-second write deadline.
    # It does not wait for the pong. Returns Closed on a closed socket.
    fn ping(data: String) Result[Unit, WebSocketError]:
        return msrt_websocket_ping(self.native, data)

    # Sends a ping frame carrying raw bytes, with the same limits and deadline as ping.
    fn ping_bytes(data: Bytes) Result[Unit, WebSocketError]:
        return msrt_websocket_ping_bytes(self.native, data)

    # Waits for the next complete message and returns it, or none once the peer closes normally.
    # A larger message returns LimitExceeded and a malformed text message InvalidData; after any receive failure the connection is closed. One receive runs at a time, and others wait their turn.
    fn receive() Result[Optional[WebSocketMessage], WebSocketError]:
        return msrt_websocket_receive(self.native)

    # Sends `data` as one text message; a payload over `max_message_bytes` returns LimitExceeded. One send runs at a time.
    fn send(data: String) Result[Unit, WebSocketError]:
        return msrt_websocket_send(self.native, data)

    # Sends `data` as one message, a text frame when `text` is True and a binary frame (the default) otherwise.
    # Text must be valid UTF-8 or the call returns InvalidData, and a payload over `max_message_bytes` returns LimitExceeded. One send runs at a time.
    fn send_bytes(data: Bytes, text: Bool = false) Result[Unit, WebSocketError]:
        return msrt_websocket_send_bytes(self.native, data, text)

    # Returns the subprotocol the server selected during the handshake, or an empty string when none was negotiated.
    fn subprotocol() String:
        return msrt_websocket_subprotocol(self.native)

# A received message and whether its payload is UTF-8 text.
export type WebSocketMessage:
    # The message payload bytes; for a text message they are the UTF-8 encoding of the text.
    data: Bytes
    # True when the peer sent a text frame, which guarantees `data` is valid UTF-8; False for a binary frame.
    text: Bool

# WebSocket message, timeout, TLS, and per-message compression settings.
export type WebSocketOptions:
    # Largest message accepted or sent, in bytes. Must be positive; none sets no limit.
    max_message_bytes: Optional[Int] = none
    # Time budget for connecting and completing the opening handshake. none waits indefinitely and a negative duration is rejected.
    timeout: Optional[Duration] = none
    # TLS settings for `wss` URLs: trusted roots, client identity, and protocols.
    tls: TlsOptions
    # When True, offers per-message compression during the handshake; it applies only if the peer agrees.
    compression: Bool

impl Error for WebSocketError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `WebSocket: <reason>`.
    fn message() String:
        match self:
            InvalidInput: return "WebSocket: invalid input"
            InvalidData: return "WebSocket: invalid data"
            LimitExceeded: return "WebSocket: limit exceeded"
            PermissionDenied: return "WebSocket: permission denied"
            Closed: return "WebSocket: resource is closed"
            Timeout: return "WebSocket: operation timed out"
            Failed(message): return message.clone()

# Serves on `cores` threads: this thread accepts from `listener` and deals each connection, round robin, to one of `cores` workers that run `entry`, a named top-level fn that ends in `serve_core(handler, options)`. A connection, and every request on it, stays on its worker, and each worker builds its own handler, so no closure or other memory crosses threads.
# Runs until accepting fails, returning that error (`Closed` after the listener was closed), or a worker's channel closes (returns `Failed`). Workers still running afterwards are cancelled.
# Returns InvalidInput when `cores` is below 1, and `Failed` when a worker cannot start.
export fn serve_cores(
    listener: Listener,
    entry: fn() Unit,
    cores: Int
) Result[Unit, NetworkError]:
    if cores < 1:
        return error(NetworkError.InvalidInput)

    let group = WorkerGroup[Int, Int]()
    let started = group.spawn_many(entry, cores)
    if started.is_error():
        return error(NetworkError.Failed("could not start a serving worker"))

    let workers = started.get()
    var next = 0

    while true:
        let accepted = listener.accept_raw(none)
        if accepted.is_error():
            return error(accepted.err().clone())
        if workers[next % cores].channel.send(accepted.get()).is_error():
            return error(NetworkError.Failed("a serving worker ended"))

        next += 1

    return ok(unit)

# Worker side of `serve_cores`: serves the connections dealt to this worker with
# `handler` and `options`, until the acceptor ends. Returns InvalidInput for invalid options.
export fn serve_core(
    handler: fn(HttpExchange) Result[Unit, HttpError],
    options: HttpServerOptions = HttpServerOptions()
) Result[Unit, HttpError]:
    var ch = worker_channel[Int, Int]()
    var server = try network().serve_connections(handler: handler, options: options)

    while true:
        if let connection = ch.receive().get(none):
            server.adopt(connection)
            continue

        break

    server.close()
    return ok(unit)
