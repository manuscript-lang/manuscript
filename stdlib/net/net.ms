import Closeable, Data from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import ClientResponse from "@std/net/http.ms"
import Duration from "@std/os/time.ms"
import HttpClient from "@std/net/http.ms"
import HttpClientOptions from "@std/net/http.ms"
import HttpExchange from "@std/net/http.ms"
import HttpHeaders from "@std/net/http.ms"
import HttpMethod from "@std/net/http.ms"
import HttpServer from "@std/net/http.ms"
import HttpServerOptions from "@std/net/http.ms"
import Timestamp from "@std/os/time.ms"
import Worker, WorkerGroup, worker_channel from "@std/concurrency/workers.ms"
import (
    msstd_url_encode_component,
    msstd_net_ip_address_text,
    msstd_net_ip_address_family,
    msstd_net_cidr_text,
    msstd_net_contains_ip,
    msstd_net_parse_cidr,
    msstd_net_parse_ip,
    msstd_net_network,
    msstd_tls_parse_certificates,
    msstd_tls_verify_certificates,
    msstd_url_decode_component,
    msstd_url_format,
    msstd_url_format_query,
    msstd_url_parse,
    msstd_url_parse_query,
    msstd_url_resolve,
    msstd_net_connection_close,
    msstd_net_connection_local_address,
    msstd_net_connection_peer_address,
    msstd_net_connection_read,
    msstd_net_connection_clone,
    msstd_net_connection_shutdown_write,
    msstd_net_connection_tls_info,
    msstd_net_connection_write,
    msstd_net_connection_write_bytes,
    msstd_net_datagram_address,
    msstd_net_datagram_close,
    msstd_net_datagram_receive,
    msstd_net_datagram_send,
    msstd_net_datagram_send_bytes,
    msstd_net_listener_accept,
    msstd_net_listener_accept_raw,
    msstd_net_listener_address,
    msstd_net_listener_close,
    msstd_net_listener_raw_owner,
    msstd_net_release_unadopted,
    msstd_websocket_close,
    msstd_websocket_ping,
    msstd_websocket_ping_bytes,
    msstd_websocket_receive,
    msstd_websocket_send,
    msstd_websocket_send_bytes,
    msstd_websocket_subprotocol
) from "@std/internal/net.ms"

# The runtime handle behind a `Connection`.
export extern type NativeConnection

# A connected stream socket, optionally protected by TLS.
# Several tasks may wait on one connection: each `read` parks until data arrives, and tasks are woken together, so the one that finds data proceeds and the rest wait again. Writers sharing a connection should serialize whole messages themselves.
export type Connection:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeConnection

impl Closeable for Connection:
    # Closes the socket, interrupting calls in progress, and waits for them to stop.
    # Safe to call repeatedly; later calls wait for the first. Reads and writes afterwards return Closed.
    var fn close() Unit!:
        msstd_net_connection_close(self.native)
        return ok(unit)

impl Connection:
    # Returns this end's address as `host:port` text, with IPv6 hosts in brackets; for Unix sockets it is the socket path.
    fn local_address() String:
        return msstd_net_connection_local_address(self.native)

    # Returns the remote end's address as `host:port` text, with IPv6 hosts in brackets.
    fn peer_address() String:
        return msstd_net_connection_peer_address(self.native)

    # Returns a positive chunk or none at EOF; a local timeout has kind `Failed`, not `Timeout`.
    fn read(max_bytes: Int?, timeout: Duration?) Bytes?!:
        return msstd_net_connection_read(self.native, max_bytes, timeout)

    # Returns a second connection over a duplicate of the socket, which closes on its own, so one task
    # can read while another writes. Both share the stream: bytes read through one are not seen by the other.
    # While a clone is open, closing a copy closes only its descriptor: the peer sees no end of stream, and a call parked on the closed copy ends at its timeout or the next data.
    # Returns Unsupported for a TLS connection, whose session state cannot be shared, and Closed on a closed connection.
    fn clone() Connection!:
        return msstd_net_connection_clone(self.native)

    # Half-closes the connection so the peer sees end of stream, while this side can keep reading.
    # Returns Unsupported for stream kinds that cannot half-close, and Closed on a closed connection.
    fn shutdown_write() Unit!:
        return msstd_net_connection_shutdown_write(self.native)

    # Returns the negotiated TLS version, cipher suite, protocol, and peer certificates.
    # A connection that is not TLS returns InvalidInput.
    fn tls_info() TlsInfo!:
        return msstd_net_connection_tls_info(self.native)

    # Writes all bytes on success; failure can leave a prefix. A local timeout has kind `Failed`.
    fn write(data: String, timeout: Duration?) Unit!:
        return msstd_net_connection_write(self.native, data, timeout)

    # Writes raw bytes with the same rules as write.
    fn write_bytes(data: Bytes, timeout: Duration?) Unit!:
        return msstd_net_connection_write_bytes(self.native, data, timeout)

# One datagram and the address from which it was received.
export type Datagram:
    # The payload bytes of this datagram, never longer than the receive call's `max_bytes`.
    data: Bytes
    # Native host:port text, with bracketed IPv6 addresses.
    sender: String

# The runtime handle behind a `DatagramSocket`.
export extern type NativeDatagramSocket

# A connectionless socket for sending and receiving datagrams.
export type DatagramSocket:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeDatagramSocket

impl Closeable for DatagramSocket:
    # Closes the socket, interrupting calls in progress, and waits for them to stop.
    # Safe to call repeatedly.
    var fn close() Unit!:
        msstd_net_datagram_close(self.native)
        return ok(unit)

impl DatagramSocket:
    # Returns the bound local address as `host:port` text, which reveals the port chosen when binding port 0.
    fn address() String:
        return msstd_net_datagram_address(self.native)

    # Waits for one datagram and returns its bytes with the sender's address. `max_bytes` is 1 through 65535 and defaults to 65535.
    # A larger datagram returns LimitExceeded and is discarded. A timeout returns Timeout and a closed socket returns Closed.
    fn receive(max_bytes: Int?, timeout: Duration?) Datagram!:
        return msstd_net_datagram_receive(self.native, max_bytes, timeout)

    # Sends `data` as a single datagram to `address` (`host:port`), resolving a host name with the network's resolver.
    # The network's restrictions apply to both the name and the resolved address. A short send returns Failed; a timeout returns Timeout.
    fn send(data: String, address: String, timeout: Duration?) Unit!:
        return msstd_net_datagram_send(self.native, data, address, timeout)

    # Sends raw bytes as a single datagram with the same rules as send.
    fn send_bytes(data: Bytes, address: String, timeout: Duration?) Unit!:
        return msstd_net_datagram_send_bytes(self.native, data, address, timeout)

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
        return msstd_net_ip_address_text(self)

    # Returns the normalized address family.
    fn family() IpFamily:
        if msstd_net_ip_address_family(self):
            return IPv6

        return IPv4

# A validated, masked numeric CIDR range.
export extern type Cidr

impl Data for Cidr:

impl Cidr:
    # Returns the canonical masked prefix without reparsing.
    fn text() String:
        return msstd_net_cidr_text(self)

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

# A listening socket that accepts incoming connections.
# Several tasks may call `accept` on one listener (an accept pool); each incoming connection goes to exactly one of them.
export type Listener:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeListener

impl Closeable for Listener:
    # Stops accepting, interrupts a pending `accept`, and waits for it to stop.
    # Safe to call repeatedly; connections already accepted stay open.
    var fn close() Unit!:
        msstd_net_listener_close(self.native)
        return ok(unit)

impl Listener:
    # Waits for the next incoming connection and returns it. A timeout returns Timeout and a closed listener returns Closed.
    # On a TLS listener the handshake completes before the connection is returned; a failed handshake drops that connection and returns Failed.
    fn accept(timeout: Duration?) Connection!:
        return msstd_net_listener_accept(self.native, timeout)

    # Waits for the next incoming connection and returns its socket handle without wrapping it, to give to `HttpServer.adopt` (on this or another thread). The caller owns the handle until then; one that is never adopted leaks its socket.
    # A timeout returns Timeout and a closed listener returns Closed. A TLS listener returns InvalidInput: the adopting server performs the handshake.
    fn accept_raw(timeout: Duration?) Int!:
        return msstd_net_listener_accept_raw(self.native, timeout)

    # Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.
    fn address() String:
        return msstd_net_listener_address(self.native)

# Reports whether an IP address belongs to a CIDR range.
export fn contains_ip(cidr: Cidr, address: IpAddress) Bool!:
    return msstd_net_contains_ip(cidr, address)

# Validates and canonicalizes an IPv4 or IPv6 CIDR range.
export fn parse_cidr(text: String) Cidr!:
    return msstd_net_parse_cidr(text)

# Validates and canonicalizes an IPv4 or IPv6 address.
export fn parse_ip(text: String) IpAddress!:
    return msstd_net_parse_ip(text)

# Network, DNS, HTTP, and WebSocket operations for the current host.
export interface Network:
    # Binds a UDP socket to `address` (`host:port`; port 0 picks a free port).
    # A restricted network without listening permission, or an address outside its CIDRs, returns PermissionDenied.
    fn bind_datagram(address: String) DatagramSocket!
    # Cancels in-flight calls and closes every connection, listener, socket, HTTP client, and server this network opened, including those of derived networks.
    # Safe to call repeatedly. A request handler of a server on this network cannot close it and faults.
    fn close() Unit
    # Resolves `address` (`host:port`) and opens a TCP connection to the first reachable permitted address.
    # Returns PermissionDenied for names or addresses a restricted network disallows, Timeout when `timeout` elapses, and Failed when every address refuses.
    fn connect(address: String, timeout: Duration?) Connection!
    # Connects over TCP to `address` and completes a TLS handshake verifying the server certificate against the system roots for `server_name`, with at least TLS 1.2.
    # An empty `server_name` returns InvalidInput, and `timeout` bounds the whole attempt.
    fn connect_tls(address: String, server_name: String, timeout: Duration?) Connection!
    # Connects over TCP to `address` and completes a TLS handshake using `options`, with at least TLS 1.2.
    # Invalid options return InvalidInput, handshake and verification failures return Failed, and `timeout` bounds the whole attempt.
    fn connect_tls_config(
        address: String,
        options: TlsOptions,
        timeout: Duration?
    ) Connection!
    # Connects to the Unix domain socket at `path`.
    # Any restricted network returns PermissionDenied because Unix sockets bypass host and CIDR checks, and an empty path returns InvalidInput. `timeout` bounds the attempt.
    fn connect_unix(path: String, timeout: Duration?) Connection!
    # Creates a reusable HTTP client with connection pooling that dials through this network, so its restrictions and resolver apply to every request and redirect.
    # Invalid or negative options return InvalidInput. Closing the network closes the client.
    fn http_client(options: HttpClientOptions) HttpClient!
    # Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
    # A restricted network needs `allow_listen` and an IP-literal address inside its CIDRs, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
    fn listen(address: String) Listener!
    # Listens for TCP connections on `address` and completes a TLS handshake for each accepted connection, within `handshake_timeout` when supplied.
    # `options` must hold a certificate and key, otherwise InvalidInput is returned.
    fn listen_tls(
        address: String,
        options: TlsOptions,
        handshake_timeout: Duration?
    ) Listener!
    # Listens on a Unix domain socket at `path`.
    # Any restricted network returns PermissionDenied, and an empty path returns InvalidInput.
    fn listen_unix(path: String) Listener!
    # Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
    # More than `max_records` addresses returns LimitExceeded, `timeout` bounds the lookup, and a failed lookup returns Failed.
    # System-resolver lookups run on the runtime's blocking threads (`MS_POOL_THREADS`, default 4), at most half of them at once, while other tasks keep running.
    fn lookup(name: String, max_records: Int?, timeout: Duration?) List[String]!
    # Performs one buffered HTTP request and returns the status, headers, and complete body.
    # Only `http` and `https` URLs without user info are accepted. Redirects are returned, not followed, and no cookies or proxy settings apply. A body over `max_response_bytes` returns LimitExceeded; error statuses are ordinary responses.
    fn request(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: String = "",
        max_response_bytes: Int?,
        timeout: Duration?
    ) ClientResponse!
    # Performs the same buffered request with a raw bytes body.
    fn request_bytes(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: Bytes = "".to_bytes(),
        max_response_bytes: Int?,
        timeout: Duration?
    ) ClientResponse!
    # Resolves the selected supported category, retaining it in each record.
    fn resolve(
        name: String,
        kind: DnsKind,
        max_records: Int?,
        timeout: Duration?
    ) List[DnsRecord]!
    # Returns a derived network limited to the given host names and CIDR ranges.
    # Names match case-insensitively without a trailing dot, and IP-literal hosts also match through `cidrs`. With `cidrs`, every resolved address must be inside one of them. `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A derived restriction can only narrow its parent, and closing the parent closes the child. Invalid host or CIDR text returns InvalidInput.
    fn restrict(hosts: List[String], cidrs: List[String], allow_listen: Bool) Network!
    # Starts an HTTP server on `address` whose handler receives each request as an exchange: read the body and write the response incrementally, or use `read_body`, `reply`, and `buffered` from `@std/net/http.ms` for whole messages. Limits, timeouts, and TLS come from `options`.
    # A request beyond `max_requests` concurrent requests is answered with 503, an oversized header block with 431, and a handler fault with 500. An address that cannot be bound returns Failed.
    # Returns PermissionDenied when a restricted network disallows listening, and InvalidInput for invalid options. Close the server to stop it.
    # A handler is cancelled when its request times out or its client disconnects (an HTTP/1 connection closes or an HTTP/2 stream is reset): its waits end, `tasks.cancelled()` turns true, and its cleanups run. A client that half-closes its end after sending the request counts as disconnected.
    # A faulting handler's frames release the heap values they own, as a cancelled handler's do. Return an error response for expected failures instead of faulting.
    fn serve(
        address: String,
        handler: fn(HttpExchange) Unit!,
        options: HttpServerOptions = HttpServerOptions()
    ) HttpServer!
    # Opens a WebSocket client connection to a `ws` or `wss` URL, sending the given headers and offering `subprotocols` in order.
    # Handshake headers such as `Upgrade`, `Connection`, `Host`, and `Sec-WebSocket-*` cannot be set. A server that selects a subprotocol that was not offered fails the handshake. Failures are `Error` values.
    fn web_socket(
        url: String,
        headers: HttpHeaders,
        subprotocols: List[String],
        options: WebSocketOptions
    ) WebSocket!
    # Starts an HTTP server that has no listener: it serves the connections handed to `HttpServer.adopt`, with the handler, limits, timeouts, and TLS of `serve`. Close the server to stop it.
    # Returns InvalidInput for invalid options.
    fn serve_connections(
        handler: fn(HttpExchange) Unit!,
        options: HttpServerOptions = HttpServerOptions()
    ) HttpServer!
    # Returns a derived network that resolves names through the DNS server at `address`, an IP literal with port, instead of the system resolver.
    # The address must be allowed by this network's restrictions, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
    fn with_resolver(address: String) Network!

# The network of the current host.
fn host_network() Network:
    return msstd_net_network()

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
export fn parse_certificates(pem: String, max_certificates: Int?) List[CertificateInfo]!:
    return msstd_tls_parse_certificates(pem, max_certificates)

# Verifies a PEM certificate chain against roots, name constraints, and the supplied time.
export fn verify_certificates(
    chain_pem: String,
    roots_pem: String,
    server_name: String,
    now: Timestamp
) Unit!:
    return msstd_tls_verify_certificates(chain_pem, roots_pem, server_name, now)

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
    port: Int?
    # Escaped path text, retaining escaped separators; format validates its percent escapes and UTF-8.
    path: String
    # Encoded query contents without the leading question mark; parse_query decodes individual entries.
    query: String
    # Decoded fragment contents without the leading hash mark.
    fragment: String

# Decodes one percent-encoded URL component. `+` is not treated as a space.
export fn decode_component(text: String) String!:
    return msstd_url_decode_component(text)

# Percent-encodes one URL component using UTF-8 bytes.
export fn encode_component(text: String) String:
    return msstd_url_encode_component(text)

# Formats URL components as an absolute hierarchical URL.
# Missing or malformed schemes and hostless relative paths return InvalidInput, as do other invalid components.
export fn format(value: Url) String!:
    return msstd_url_format(value)

# Encodes query entries as a query string.
export fn format_query(entries: List[QueryEntry]) String:
    return msstd_url_format_query(entries)

# Parses an absolute URL into its components.
export fn parse(text: String) Url!:
    return msstd_url_parse(text)

# Parses a query string, preserving duplicate keys and their input order.
export fn parse_query(text: String, max_entries: Int?) List[QueryEntry]!:
    return msstd_url_parse_query(text, max_entries)

# Resolves a relative reference against a base URL.
export fn resolve(base: Url, reference: String) Url!:
    return msstd_url_resolve(base, reference)

# The runtime handle behind a `WebSocket`.
export extern type NativeWebSocket

# A WebSocket connection. Send and receive byte messages with an explicit text flag.
export type WebSocket:
    # The runtime handle; it is released by `close` and owned by this value.
    native: NativeWebSocket

impl Closeable for WebSocket:
    # Sends a normal-closure frame, waiting at most about 100 ms to write it, then closes the connection and waits for in-flight calls to stop.
    # Safe to call repeatedly; later calls wait for the first.
    var fn close() Unit!:
        msstd_websocket_close(self.native)
        return ok(unit)

impl WebSocket:
    # Sends a ping frame carrying `data`, which must be at most 125 bytes, with a one-second write deadline.
    # It does not wait for the pong. Returns Closed on a closed socket.
    fn ping(data: String) Unit!:
        return msstd_websocket_ping(self.native, data)

    # Sends a ping frame carrying raw bytes, with the same limits and deadline as ping.
    fn ping_bytes(data: Bytes) Unit!:
        return msstd_websocket_ping_bytes(self.native, data)

    # Waits for the next complete message and returns it, or none once the peer closes normally.
    # A larger message returns LimitExceeded and a malformed text message InvalidData; after any receive failure the connection is closed. One receive runs at a time, and others wait their turn.
    fn receive() WebSocketMessage?!:
        return msstd_websocket_receive(self.native)

    # Sends `data` as one text message; a payload over `max_message_bytes` returns LimitExceeded. One send runs at a time.
    fn send(data: String) Unit!:
        return msstd_websocket_send(self.native, data)

    # Sends `data` as one message, a text frame when `text` is True and a binary frame (the default) otherwise.
    # Text must be valid UTF-8 or the call returns InvalidData, and a payload over `max_message_bytes` returns LimitExceeded. One send runs at a time.
    fn send_bytes(data: Bytes, text: Bool = false) Unit!:
        return msstd_websocket_send_bytes(self.native, data, text)

    # Returns the subprotocol the server selected during the handshake, or an empty string when none was negotiated.
    fn subprotocol() String:
        return msstd_websocket_subprotocol(self.native)

# A received message and whether its payload is UTF-8 text.
export type WebSocketMessage:
    # The message payload bytes; for a text message they are the UTF-8 encoding of the text.
    data: Bytes
    # True when the peer sent a text frame, which guarantees `data` is valid UTF-8; False for a binary frame.
    text: Bool

# WebSocket message, timeout, TLS, and per-message compression settings.
export type WebSocketOptions:
    # Largest message accepted or sent, in bytes. Must be positive; none sets no limit.
    max_message_bytes: Int?
    # Time budget for connecting and completing the opening handshake. none waits indefinitely and a negative duration is rejected.
    timeout: Duration?
    # TLS settings for `wss` URLs: trusted roots, client identity, and protocols.
    tls: TlsOptions
    # When True, offers per-message compression during the handshake; it applies only if the peer agrees.
    compression: Bool

# Serves on `cores` threads: this thread accepts from `listener` and deals each connection, round robin, to one of `cores` workers that run `entry`, a named top-level fn that ends in `serve_core(handler, options)`. A connection, and every request on it, stays on its worker, and each worker builds its own handler, so no closure or other memory crosses threads.
# Runs until accepting fails, returning that error (`Closed` after the listener was closed), or a worker's channel closes (returns `Failed`). Workers still running afterwards are cancelled.
# Returns InvalidInput when `cores` is below 1, and `Failed` when a worker cannot start.
export fn serve_cores(listener: Listener, entry: fn() Unit, cores: Int) Unit!:
    if cores < 1:
        return error(Error("network: invalid input", kind: InvalidInput))

    var serving = Serving(
        group: WorkerGroup[Int, Int](),
        owner: msstd_net_listener_raw_owner(listener.native)
    )
    let started = serving.group.spawn_many(entry, cores)
    if started.is_error():
        return error(Error("network: could not start a serving worker", kind: Failed))

    return deal(listener, started.get())

# The workers of `serve_cores` and the owner key of the listener whose unadopted handles go with them.
# Its close runs on every exit, a cancellation included.
type Serving:
    group: WorkerGroup[Int, Int]
    owner: Int

impl Closeable for Serving:
    # Ends the workers first, so no adopter can still claim a handle that stays unadopted, then closes those handles.
    var fn close() Unit!:
        self.group.close().get(none)
        msstd_net_release_unadopted(self.owner)
        return ok(unit)

# Deals accepted connections round robin to `workers` until accepting or a send fails.
fn deal(listener: Listener, workers: List[Worker[Int, Int]]) Unit!:
    var next = 0

    while true:
        let accepted = listener.accept_raw(none)
        if accepted.is_error():
            return error(accepted.err().clone())
        if workers[next % workers.length()].channel.send(accepted.get()).is_error():
            return error(Error("network: a serving worker ended", kind: Failed))

        next += 1

    return ok(unit)

# Worker side of `serve_cores`: serves the connections dealt to this worker with
# `handler` and `options`, until the acceptor ends. Returns InvalidInput for invalid options.
export fn serve_core(
    handler: fn(HttpExchange) Unit!,
    options: HttpServerOptions = HttpServerOptions()
) Unit!:
    var ch = worker_channel[Int, Int]()
    var server = try serve_connections(handler: handler, options: options)

    while true:
        if let connection = ch.receive().get(none):
            server.adopt(connection)
            continue

        break

    server.close().get(none)
    return ok(unit)

# Binds a UDP socket to `address` (`host:port`; port 0 picks a free port).
# A restricted network without listening permission, or an address outside its CIDRs, returns PermissionDenied.
export fn bind_datagram(address: String) DatagramSocket!:
    return host_network().bind_datagram(address)

# Resolves `address` (`host:port`) and opens a TCP connection to the first reachable permitted address.
# Returns PermissionDenied for names or addresses a restricted network disallows, Timeout when `timeout` elapses, and Failed when every address refuses.
export fn connect(address: String, timeout: Duration?) Connection!:
    return host_network().connect(address, timeout)

# Connects over TCP to `address` and completes a TLS handshake verifying the server certificate against the system roots for `server_name`, with at least TLS 1.2.
# An empty `server_name` returns InvalidInput, and `timeout` bounds the whole attempt.
export fn connect_tls(
    address: String,
    server_name: String,
    timeout: Duration?
) Connection!:
    return host_network().connect_tls(address, server_name, timeout)

# Connects over TCP to `address` and completes a TLS handshake using `options`, with at least TLS 1.2.
# Invalid options return InvalidInput, handshake and verification failures return Failed, and `timeout` bounds the whole attempt.
export fn connect_tls_config(
    address: String,
    options: TlsOptions,
    timeout: Duration?
) Connection!:
    return host_network().connect_tls_config(address, options, timeout)

# Connects to the Unix domain socket at `path`.
# Any restricted network returns PermissionDenied because Unix sockets bypass host and CIDR checks, and an empty path returns InvalidInput. `timeout` bounds the attempt.
export fn connect_unix(path: String, timeout: Duration?) Connection!:
    return host_network().connect_unix(path, timeout)

# Creates a reusable HTTP client with connection pooling that dials through this network, so its restrictions and resolver apply to every request and redirect.
# Invalid or negative options return InvalidInput. Closing the network closes the client.
export fn http_client(options: HttpClientOptions) HttpClient!:
    return host_network().http_client(options)

# Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
# A restricted network needs `allow_listen` and an IP-literal address inside its CIDRs, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
export fn listen(address: String) Listener!:
    return host_network().listen(address)

# Listens for TCP connections on `address` and completes a TLS handshake for each accepted connection, within `handshake_timeout` when supplied.
# `options` must hold a certificate and key, otherwise InvalidInput is returned.
export fn listen_tls(
    address: String,
    options: TlsOptions,
    handshake_timeout: Duration?
) Listener!:
    return host_network().listen_tls(address, options, handshake_timeout)

# Listens on a Unix domain socket at `path`.
# Any restricted network returns PermissionDenied, and an empty path returns InvalidInput.
export fn listen_unix(path: String) Listener!:
    return host_network().listen_unix(path)

# Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
# More than `max_records` addresses returns LimitExceeded, `timeout` bounds the lookup, and a failed lookup returns Failed.
# System-resolver lookups run on the runtime's blocking threads (`MS_POOL_THREADS`, default 4), at most half of them at once, while other tasks keep running.
export fn lookup(name: String, max_records: Int?, timeout: Duration?) List[String]!:
    return host_network().lookup(name, max_records, timeout)

# Performs one buffered HTTP request and returns the status, headers, and complete body.
# Only `http` and `https` URLs without user info are accepted. Redirects are returned, not followed, and no cookies or proxy settings apply. A body over `max_response_bytes` returns LimitExceeded; error statuses are ordinary responses.
export fn request(
    method: HttpMethod,
    url: String,
    headers: HttpHeaders,
    body: String = "",
    max_response_bytes: Int?,
    timeout: Duration?
) ClientResponse!:
    return host_network().request(
        method, url, headers, body, max_response_bytes, timeout
    )

# Performs the same buffered request with a raw bytes body.
export fn request_bytes(
    method: HttpMethod,
    url: String,
    headers: HttpHeaders,
    body: Bytes = "".to_bytes(),
    max_response_bytes: Int?,
    timeout: Duration?
) ClientResponse!:
    return host_network().request_bytes(
        method, url, headers, body, max_response_bytes, timeout
    )

# Resolves the selected supported category, retaining it in each record.
export fn resolve_dns(
    name: String,
    kind: DnsKind,
    max_records: Int?,
    timeout: Duration?
) List[DnsRecord]!:
    return host_network().resolve(name, kind, max_records, timeout)

# Returns a derived network limited to the given host names and CIDR ranges.
# Names match case-insensitively without a trailing dot, and IP-literal hosts also match through `cidrs`. With `cidrs`, every resolved address must be inside one of them. `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A derived restriction can only narrow its parent, and closing the parent closes the child. Invalid host or CIDR text returns InvalidInput.
export fn restrict(
    hosts: List[String],
    cidrs: List[String],
    allow_listen: Bool
) Network!:
    return host_network().restrict(hosts, cidrs, allow_listen)

# Starts an HTTP server on `address` whose handler receives each request as an exchange: read the body and write the response incrementally, or use `read_body`, `reply`, and `buffered` from `@std/net/http.ms` for whole messages. Limits, timeouts, and TLS come from `options`.
# A request beyond `max_requests` concurrent requests is answered with 503, an oversized header block with 431, and a handler fault with 500. An address that cannot be bound returns Failed.
# Returns PermissionDenied when a restricted network disallows listening, and InvalidInput for invalid options. Close the server to stop it.
# A handler is cancelled when its request times out or its client disconnects (an HTTP/1 connection closes or an HTTP/2 stream is reset): its waits end, `tasks.cancelled()` turns true, and its cleanups run. A client that half-closes its end after sending the request counts as disconnected.
# A faulting handler's frames release the heap values they own, as a cancelled handler's do. Return an error response for expected failures instead of faulting.
export fn serve(
    address: String,
    handler: fn(HttpExchange) Unit!,
    options: HttpServerOptions = HttpServerOptions()
) HttpServer!:
    return host_network().serve(address, handler, options)

# Opens a WebSocket client connection to a `ws` or `wss` URL, sending the given headers and offering `subprotocols` in order.
# Handshake headers such as `Upgrade`, `Connection`, `Host`, and `Sec-WebSocket-*` cannot be set. A server that selects a subprotocol that was not offered fails the handshake. Failures are `Error` values.
export fn web_socket(
    url: String,
    headers: HttpHeaders,
    subprotocols: List[String],
    options: WebSocketOptions
) WebSocket!:
    return host_network().web_socket(url, headers, subprotocols, options)

# Starts an HTTP server that has no listener: it serves the connections handed to `HttpServer.adopt`, with the handler, limits, timeouts, and TLS of `serve`. Close the server to stop it.
# Returns InvalidInput for invalid options.
export fn serve_connections(
    handler: fn(HttpExchange) Unit!,
    options: HttpServerOptions = HttpServerOptions()
) HttpServer!:
    return host_network().serve_connections(handler, options)

# Returns a derived network that resolves names through the DNS server at `address`, an IP literal with port, instead of the system resolver.
# The address must be allowed by this network's restrictions, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
export fn with_resolver(address: String) Network!:
    return host_network().with_resolver(address)
