import Closeable, Data from "@std/core.ms"
import ReadStream, WriteStream, Source, Sink, stream, writer from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import ClientResponse from "@std/net/http.ms"
import Duration from "@std/os/time.ms"
import HttpClient from "@std/net/http.ms"
import HttpClientOptions from "@std/net/http.ms"
import HttpExchange from "@std/net/http.ms"
import HttpHeaders from "@std/net/http.ms"
import HttpMethod from "@std/net/http.ms"
import HttpServer from "@std/net/http.ms"
import NativeServing from "@std/net/http.ms"
import HttpServerOptions from "@std/net/http.ms"
import Timestamp from "@std/os/time.ms"
import Promise, promise, deferred, complete from "@std/concurrency/promise.ms"
import sleep from "@std/os/time.ms"
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
    msstd_net_connection_share,
    msstd_net_connection_close_if_last,
    msstd_net_connection_local_address,
    msstd_net_connection_peer_address,
    msstd_net_connection_read,
    msstd_net_connection_shutdown_write,
    msstd_net_connection_tls_info,
    msstd_net_connection_write_bytes,
    msstd_net_datagram_address,
    msstd_net_datagram_close,
    msstd_net_datagram_share,
    msstd_net_datagram_close_if_last,
    msstd_net_datagram_receive,
    msstd_net_datagram_send_bytes,
    msstd_net_listener_accept,
    msstd_net_listener_accept_raw,
    msstd_net_listener_address,
    msstd_net_listener_close,
    msstd_net_listener_raw_owner,
    msstd_net_release_unadopted,
    msstd_websocket_close,
    msstd_websocket_share,
    msstd_websocket_close_if_last,
    msstd_websocket_ping,
    msstd_websocket_ping_bytes,
    msstd_websocket_receive,
    msstd_websocket_send_bytes,
    msstd_websocket_subprotocol
) from "@std/internal/net.ms"
import (
    msstd_http_serving_new,
    msstd_http_serving_share,
    msstd_http_serving_address,
    msstd_http_serving_accept,
    msstd_http_serving_connect,
    msstd_http_serving_release,
    msrt_runtime_set_threads
) from "@std/internal/http.ms"

// The runtime handle behind a `RawConnection`.
export extern type NativeConnection

// The native socket a network operation returns; `connection` wraps it into a `Connection`.
export type RawConnection:
    // The runtime handle; it is released when the last end closes.
    native: NativeConnection

type ConnectionSource:
    raw: RawConnection

impl Source[Bytes] for ConnectionSource:
    // Waits for the next chunk; none at the end of the stream.
    var fn next() Bytes?!:
        return msstd_net_connection_read(self.raw.native, none, none)

    // Closes the socket when the output end is already closed.
    var fn close() Unit!:
        msstd_net_connection_close_if_last(self.raw.native)
        return ok(unit)

type ConnectionSink:
    raw: RawConnection

impl Sink[Bytes] for ConnectionSink:
    var fn put(value: Bytes) Unit!:
        return msstd_net_connection_write_bytes(self.raw.native, value, none)

    var fn drain() Promise[Unit]:
        return deferred[Unit](fn(id: Int) Unit: complete[Unit](id, ok(unit)))

    fn buffered() Int:
        return 0

    // Half-closes the connection so the peer sees the end of the stream; the socket closes once the input is closed too.
    var fn close() Unit!:
        let _ = msstd_net_connection_shutdown_write(self.raw.native)
        msstd_net_connection_close_if_last(self.raw.native)
        return ok(unit)

// What is known about a connection, available after its streams are moved elsewhere.
export type ConnectionInfo:
    // This end's address as `host:port` text, with IPv6 hosts in brackets; for Unix sockets it is the socket path.
    local_address: String
    // The remote end's address as `host:port` text, with IPv6 hosts in brackets.
    peer_address: String
    // The negotiated TLS version, cipher suite, protocol, and peer certificates; none when the connection is not TLS.
    tls: TlsInfo?

impl ConnectionInfo:
    // Returns the negotiated TLS version, cipher suite, protocol, and peer certificates.
    // A connection that is not TLS returns InvalidInput.
    fn tls_info() TlsInfo!:
        if let info = self.tls:
            return ok(info.clone())
        return error(Error("network: invalid input", kind: ErrorCategory.InvalidInput))

/*
A connected stream socket, optionally protected by TLS: `input` reads chunks until the peer's end of stream, and
`output` writes chunks. Move the two streams to different tasks to read and write at once. Closing `output` half-closes
the connection; the socket closes when both streams are closed, which is also what closing the `Connection` does.
*/
export type Connection:
    // Bytes from the peer; a read ends with none at the peer's end of stream.
    input: ReadStream[Bytes]
    // Bytes to the peer. Closing it half-closes the connection.
    output: WriteStream[Bytes]
    // Addresses and TLS details.
    info: ConnectionInfo

impl Closeable for Connection:
    // Closes both streams, and with them the socket.
    var fn close() Unit!:
        try self.input.close()
        return self.output.close()

// Wraps a native socket into a `Connection`.
fn connection(raw: RawConnection) Connection:
    let local = msstd_net_connection_local_address(raw.native)
    let peer = msstd_net_connection_peer_address(raw.native)
    var tls: TlsInfo? = none
    match msstd_net_connection_tls_info(raw.native):
        ok(found): tls = found
        error(_): tls = none
    let other = RawConnection(msstd_net_connection_share(raw.native))
    return Connection(
        input: stream[Bytes](ConnectionSource(raw)),
        output: writer[Bytes](ConnectionSink(other)),
        info: ConnectionInfo(local, peer, tls)
    )

// One datagram. Received, `address` is where it came from; written, where it goes.
export type Datagram:
    // The payload bytes of this datagram, at most 65535 bytes.
    data: Bytes
    // Native host:port text, with bracketed IPv6 addresses.
    address: String

// The runtime handle behind a `RawDatagramSocket`.
export extern type NativeDatagramSocket

// The native socket `bind_datagram` returns; it is wrapped into a `DatagramSocket`.
export type RawDatagramSocket:
    // The runtime handle; it is released when the last end closes.
    native: NativeDatagramSocket

type DatagramSource:
    raw: RawDatagramSocket

impl Source[Datagram] for DatagramSource:
    // Waits for one datagram, at most 65535 bytes; a larger one is an error of kind `LimitExceeded` and is discarded.
    var fn next() Datagram?!:
        return ok(try msstd_net_datagram_receive(self.raw.native, none, none))

    var fn close() Unit!:
        msstd_net_datagram_close_if_last(self.raw.native)
        return ok(unit)

type DatagramSink:
    raw: RawDatagramSocket

impl Sink[Datagram] for DatagramSink:
    // Sends `value.data` as one datagram to `value.address`, resolving a host name with the network's resolver.
    var fn put(value: Datagram) Unit!:
        return msstd_net_datagram_send_bytes(self.raw.native, value.data, value.address, none)

    var fn drain() Promise[Unit]:
        return deferred[Unit](fn(id: Int) Unit: complete[Unit](id, ok(unit)))

    fn buffered() Int:
        return 0

    var fn close() Unit!:
        msstd_net_datagram_close_if_last(self.raw.native)
        return ok(unit)

// A connectionless socket for sending and receiving datagrams. Closing it closes both streams.
export type DatagramSocket:
    // Datagrams received, with the sender's address.
    input: ReadStream[Datagram]
    // Datagrams to send; each carries its destination.
    output: WriteStream[Datagram]
    // The bound local address as `host:port` text, which reveals the port chosen when binding port 0.
    address: String

impl Closeable for DatagramSocket:
    var fn close() Unit!:
        try self.input.close()
        return self.output.close()

fn datagram_socket(raw: RawDatagramSocket) DatagramSocket:
    let address = msstd_net_datagram_address(raw.native)
    let other = RawDatagramSocket(msstd_net_datagram_share(raw.native))
    return DatagramSocket(
        input: stream[Datagram](DatagramSource(raw)),
        output: writer[Datagram](DatagramSink(other)),
        address: address
    )

// Supported DNS query categories; unknown spellings are rejected by checking.
export type DnsKind:
    case A  // IPv4 address records for the queried name.
    case AAAA  // IPv6 address records for the queried name.
    case CNAME  // Canonical name alias records for the queried name.
    case MX  // Mail exchange records with priority values.
    case NS  // Name server records for the queried zone.
    case TXT  // Text records returned as string values.
    case PTR  // Reverse address pointer records for an IP.
    case SRV  // Service location records with priority, weight and port.

impl DnsKind:
    // Returns the uppercase wire category.
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

// Numeric address families reported by IP values and host interfaces.
export type IpFamily:
    case IPv4  // A four-byte numeric address.
    case IPv6  // A sixteen-byte numeric address.

impl IpFamily:
    // Returns IPv4 or IPv6.
    fn text() String:
        match self:
            IPv4: return "IPv4"
            IPv6: return "IPv6"

// A validated numeric IPv4/IPv6 address without a port or zone.
export extern type IpAddress

impl Data for IpAddress:

impl IpAddress:
    // Returns canonical text; mapped IPv6 input is normalized to IPv4.
    fn text() String:
        return msstd_net_ip_address_text(self)

    // Returns the normalized address family.
    fn family() IpFamily:
        if msstd_net_ip_address_family(self):
            return IPv6

        return IPv4

// A validated, masked numeric CIDR range.
export extern type Cidr

impl Data for Cidr:

impl Cidr:
    // Returns the canonical masked prefix without reparsing.
    fn text() String:
        return msstd_net_cidr_text(self)

// DNS record data returned by a typed lookup.
export type DnsRecord:
    // The same typed category used by the query.
    kind: DnsKind
    // The record's answer: an IP address for A and AAAA, the target host name for CNAME, MX, NS, PTR, and SRV, or the text for TXT.
    value: String
    // The preference of an MX record or the priority of an SRV record, where lower values are tried first; 0 for other kinds.
    priority: Int
    // The relative weight of an SRV record among targets with the same priority; 0 for other kinds.
    weight: Int
    // The service port of an SRV record; 0 for other kinds.
    port: Int

// The runtime handle behind a `Listener`.
export extern type NativeListener

// A listening socket that accepts incoming connections.
// Several tasks may call `accept` on one listener (an accept pool); each incoming connection goes to exactly one of them.
export type Listener:
    // The runtime handle; it is released by `close` and owned by this value.
    native: NativeListener

impl Closeable for Listener:
    // Stops accepting, interrupts a pending `accept`, and waits for it to stop.
    // Safe to call repeatedly; connections already accepted stay open.
    var fn close() Unit!:
        msstd_net_listener_close(self.native)
        return ok(unit)

impl Listener:
    // Waits for the next incoming connection and returns it. A timeout returns Timeout and a closed listener returns Closed.
    // On a TLS listener the handshake completes before the connection is returned; a failed handshake drops that connection and returns Failed.
    fn accept(timeout: Duration?) Connection!:
        let raw = try msstd_net_listener_accept(self.native, timeout)
        return ok(connection(raw))

    // Waits for the next incoming connection and returns its socket handle without wrapping it, to give to `HttpServer.adopt` (on this or another thread). The caller owns the handle until then; one that is never adopted leaks its socket.
    // A timeout returns Timeout and a closed listener returns Closed. A TLS listener returns InvalidInput: the adopting server performs the handshake.
    fn accept_raw(timeout: Duration?) Int!:
        return msstd_net_listener_accept_raw(self.native, timeout)

    // Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.
    fn address() String:
        return msstd_net_listener_address(self.native)

// Reports whether an IP address belongs to a CIDR range.
export fn contains_ip(cidr: Cidr, address: IpAddress) Bool!:
    return msstd_net_contains_ip(cidr, address)

// Validates and canonicalizes an IPv4 or IPv6 CIDR range.
export fn parse_cidr(text: String) Cidr!:
    return msstd_net_parse_cidr(text)

// Validates and canonicalizes an IPv4 or IPv6 address.
export fn parse_ip(text: String) IpAddress!:
    return msstd_net_parse_ip(text)

// Network, DNS, HTTP, and WebSocket operations for the current host.
export interface Network:
    // Binds a UDP socket to `address` (`host:port`; port 0 picks a free port).
    // A restricted network without listening permission, or an address outside its CIDRs, returns PermissionDenied.
    fn bind_datagram(address: String) RawDatagramSocket!
    // Cancels in-flight calls and closes every connection, listener, socket, HTTP client, and server this network opened, including those of derived networks.
    // Safe to call repeatedly. A request handler of a server on this network cannot close it and faults.
    fn close() Unit
    // Resolves `address` (`host:port`) and opens a TCP connection to the first reachable permitted address.
    // Returns PermissionDenied for names or addresses a restricted network disallows, Timeout when `timeout` elapses, and Failed when every address refuses.
    fn connect(address: String, timeout: Duration?) RawConnection!
    // Connects over TCP to `address` and completes a TLS handshake verifying the server certificate against the system roots for `server_name`, with at least TLS 1.2.
    // An empty `server_name` returns InvalidInput, and `timeout` bounds the whole attempt.
    fn connect_tls(address: String, server_name: String, timeout: Duration?) RawConnection!
    // Connects over TCP to `address` and completes a TLS handshake using `options`, with at least TLS 1.2.
    // Invalid options return InvalidInput, handshake and verification failures return Failed, and `timeout` bounds the whole attempt.
    fn connect_tls_config(
        address: String,
        options: TlsOptions,
        timeout: Duration?
    ) RawConnection!
    // Connects to the Unix domain socket at `path`.
    // Any restricted network returns PermissionDenied because Unix sockets bypass host and CIDR checks, and an empty path returns InvalidInput. `timeout` bounds the attempt.
    fn connect_unix(path: String, timeout: Duration?) RawConnection!
    // Creates a reusable HTTP client with connection pooling that dials through this network, so its restrictions and resolver apply to every request and redirect.
    // Invalid or negative options return InvalidInput. Closing the network closes the client.
    fn http_client(options: HttpClientOptions) HttpClient!
    // Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
    // A restricted network needs `allow_listen` and an IP-literal address inside its CIDRs, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
    fn listen(address: String) Listener!
    // Listens for TCP connections on `address` and completes a TLS handshake for each accepted connection, within `handshake_timeout` when supplied.
    // `options` must hold a certificate and key, otherwise InvalidInput is returned.
    fn listen_tls(
        address: String,
        options: TlsOptions,
        handshake_timeout: Duration?
    ) Listener!
    // Listens on a Unix domain socket at `path`.
    // Any restricted network returns PermissionDenied, and an empty path returns InvalidInput.
    fn listen_unix(path: String) Listener!
    /*
    Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
    More than `max_records` addresses returns LimitExceeded, `timeout` bounds the lookup, and a failed lookup returns Failed.
    System-resolver lookups run on the runtime's blocking threads (`MS_POOL_THREADS`, default 4), at most half of them at once, while other tasks keep running.
    */
    fn lookup(name: String, max_records: Int?, timeout: Duration?) List[String]!
    // Performs one buffered HTTP request and returns the status, headers, and complete body.
    // Only `http` and `https` URLs without user info are accepted. Redirects are returned, not followed, and no cookies or proxy settings apply. A body over `max_response_bytes` returns LimitExceeded; error statuses are ordinary responses.
    fn request(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: String = "",
        max_response_bytes: Int?,
        timeout: Duration?
    ) ClientResponse!
    // Performs the same buffered request with a raw bytes body.
    fn request_bytes(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: Bytes = "".to_bytes(),
        max_response_bytes: Int?,
        timeout: Duration?
    ) ClientResponse!
    // Resolves the selected supported category, retaining it in each record.
    fn resolve(
        name: String,
        kind: DnsKind,
        max_records: Int?,
        timeout: Duration?
    ) List[DnsRecord]!
    // Returns a derived network limited to the given host names and CIDR ranges.
    // Names match case-insensitively without a trailing dot, and IP-literal hosts also match through `cidrs`. With `cidrs`, every resolved address must be inside one of them. `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A derived restriction can only narrow its parent, and closing the parent closes the child. Invalid host or CIDR text returns InvalidInput.
    fn restrict(hosts: List[String], cidrs: List[String], allow_listen: Bool) Network!
    // Opens a WebSocket client connection to a `ws` or `wss` URL, sending the given headers and offering `subprotocols` in order.
    // Handshake headers such as `Upgrade`, `Connection`, `Host`, and `Sec-WebSocket-*` cannot be set. A server that selects a subprotocol that was not offered fails the handshake. Failures are `Error` values.
    fn web_socket(
        url: String,
        headers: HttpHeaders,
        subprotocols: List[String],
        options: WebSocketOptions
    ) RawWebSocket!
    // Returns a derived network that resolves names through the DNS server at `address`, an IP literal with port, instead of the system resolver.
    // The address must be allowed by this network's restrictions, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
    fn with_resolver(address: String) Network!

// The network of the current host.
fn host_network() Network:
    return msstd_net_network()

// Parsed certificate identity, validity range, and original DER bytes.
export type CertificateInfo:
    // The certificate subject as a distinguished-name string, such as `CN=example.com,O=Example`.
    subject: String
    // The issuing authority as a distinguished-name string, in the same format as `subject`.
    issuer: String
    // DNS subject alternative names in certificate order; empty when the certificate has none.
    dns_names: List[String]
    // Start of the validity period as a UTC Timestamp.
    not_before: Timestamp
    // End of the validity period as a UTC Timestamp.
    not_after: Timestamp
    // The certificate's binary DER encoding, as a copy independent of the PEM text.
    der: Bytes

// Negotiated TLS version, cipher, protocol, and peer certificate information.
export type TlsInfo:
    // Negotiated protocol version as its numeric wire code, such as 771 (0x0303) for TLS 1.2 or 772 (0x0304) for TLS 1.3.
    version: Int
    // Negotiated cipher suite as its numeric IANA identifier, such as 4865 (0x1301) for TLS_AES_128_GCM_SHA256.
    cipher_suite: Int
    // The application protocol both sides agreed on, or an empty string when none was negotiated.
    alpn: String
    // The peer's presented certificates as DER bytes, leaf first; empty when the peer sent none.
    peer_certificates: List[Bytes]
    // True when the peer's certificate chain was verified against the configured roots; False when no peer chain was verified.
    verified: Bool

// Client or server TLS settings, including roots, certificates, and ALPN protocols.
export type TlsOptions:
    // Host name a TLS client sends for server name indication and matches against the server certificate; it must be non-empty for `connect_tls_config`.
    // HTTP and WebSocket clients take the name from the URL host and ignore this field, and servers do not use it.
    server_name: String
    // PEM certificates to trust. Clients use them instead of the system roots; servers use them to verify client certificates. An empty string selects the system roots; invalid PEM is rejected.
    roots_pem: String
    // PEM certificate chain this side presents, paired with `private_key_pem`. Servers must supply it; clients supply it only for mutual TLS.
    certificate_pem: String
    // PEM private key matching `certificate_pem`. Both must be set together and match, or setup fails.
    private_key_pem: String
    // Application-layer protocols to offer or accept, in preference order, such as `h2` or `http/1.1`. Each must be 1 through 255 bytes; empty disables negotiation.
    alpn: List[String]
    // Servers only: when True, a client must present a certificate that verifies against `roots_pem`. Setting it on a client configuration is rejected.
    require_client_certificate: Bool

// Parses PEM certificates and optionally limits the number returned.
export fn parse_certificates(pem: String, max_certificates: Int?) List[CertificateInfo]!:
    return msstd_tls_parse_certificates(pem, max_certificates)

// Verifies a PEM certificate chain against roots, name constraints, and the supplied time.
export fn verify_certificates(
    chain_pem: String,
    roots_pem: String,
    server_name: String,
    now: Timestamp
) Unit!:
    return msstd_tls_verify_certificates(chain_pem, roots_pem, server_name, now)

// One decoded key and value in a URL query string.
export type QueryEntry:
    // Decoded query key; duplicate keys retain separate entries in input order.
    key: String
    // Decoded query value; a bare key has an empty value and plus decodes as a space.
    value: String

// Parsed URL components. A missing port is represented by `none`.
export type Url:
    // URL scheme, lowercased during parsing; native parse rejects missing schemes and opaque URLs.
    scheme: String
    // Lowercased hostname, excluding the port and IPv6 brackets; user information is rejected.
    host: String
    // Explicit numeric port in 0..65535, or none when the input has no port.
    port: Int?
    // Escaped path text, retaining escaped separators; format validates its percent escapes and UTF-8.
    path: String
    // Encoded query contents without the leading question mark; parse_query decodes individual entries.
    query: String
    // Decoded fragment contents without the leading hash mark.
    fragment: String

// Decodes one percent-encoded URL component. `+` is not treated as a space.
export fn decode_component(text: String) String!:
    return msstd_url_decode_component(text)

// Percent-encodes one URL component using UTF-8 bytes.
export fn encode_component(text: String) String:
    return msstd_url_encode_component(text)

// Formats URL components as an absolute hierarchical URL.
// Missing or malformed schemes and hostless relative paths return InvalidInput, as do other invalid components.
export fn format(value: Url) String!:
    return msstd_url_format(value)

// Encodes query entries as a query string.
export fn format_query(entries: List[QueryEntry]) String:
    return msstd_url_format_query(entries)

// Parses an absolute URL into its components.
export fn parse(text: String) Url!:
    return msstd_url_parse(text)

// Parses a query string, preserving duplicate keys and their input order.
export fn parse_query(text: String, max_entries: Int?) List[QueryEntry]!:
    return msstd_url_parse_query(text, max_entries)

// Resolves a relative reference against a base URL.
export fn resolve(base: Url, reference: String) Url!:
    return msstd_url_resolve(base, reference)

// The runtime handle behind a `RawWebSocket`.
export extern type NativeWebSocket

// The native WebSocket a handshake returns; it is wrapped into a `WebSocket`.
export type RawWebSocket:
    // The runtime handle; it is released when the last end closes.
    native: NativeWebSocket

// The kind of a WebSocket message.
export type WebSocketKind:
    case Text  // A text frame: the payload is valid UTF-8.
    case Binary  // A binary frame.
    case Ping  // A ping control frame, at most 125 bytes; written only, the peer's pongs are answered automatically.

// One WebSocket message.
export type WebSocketMessage:
    // The payload bytes; for a text message they are the UTF-8 encoding of the text.
    data: Bytes
    kind: WebSocketKind

// A message as the native layer reports it.
export type RawWebSocketMessage:
    data: Bytes
    text: Bool

type WebSocketSource:
    raw: RawWebSocket

impl Source[WebSocketMessage] for WebSocketSource:
    // Waits for the next complete message; none once the peer closes normally.
    // A larger message is `LimitExceeded` and a malformed text message `InvalidData`; after any failure the connection is closed.
    var fn next() WebSocketMessage?!:
        let raw = try msstd_websocket_receive(self.raw.native)
        if let message = raw:
            var kind = WebSocketKind.Binary
            if message.text:
                kind = WebSocketKind.Text
            return ok(WebSocketMessage(message.data, kind))
        return ok(none)

    var fn close() Unit!:
        msstd_websocket_close_if_last(self.raw.native)
        return ok(unit)

type WebSocketSink:
    raw: RawWebSocket

impl Sink[WebSocketMessage] for WebSocketSink:
    // Sends one message. Text must be valid UTF-8 or the call returns InvalidData, and a payload over `max_message_bytes` returns LimitExceeded.
    var fn put(value: WebSocketMessage) Unit!:
        match value.kind:
            Text: return msstd_websocket_send_bytes(self.raw.native, value.data, true)
            Binary: return msstd_websocket_send_bytes(self.raw.native, value.data, false)
            Ping: return msstd_websocket_ping_bytes(self.raw.native, value.data)

    var fn drain() Promise[Unit]:
        return deferred[Unit](fn(id: Int) Unit: complete[Unit](id, ok(unit)))

    fn buffered() Int:
        return 0

    var fn close() Unit!:
        msstd_websocket_close_if_last(self.raw.native)
        return ok(unit)

/*
A WebSocket connection: `input` reads whole messages and `output` writes them. Move the streams to different tasks to
receive and send at once. The connection closes, after a normal-closure frame, when both streams are closed, which is
also what closing the `WebSocket` does.
*/
export type WebSocket:
    // Messages from the peer; none once the peer closes normally.
    input: ReadStream[WebSocketMessage]
    // Messages to the peer.
    output: WriteStream[WebSocketMessage]
    // The subprotocol the server selected during the handshake, or an empty string when none was negotiated.
    subprotocol: String

impl Closeable for WebSocket:
    // Closes both streams, and with them the connection.
    var fn close() Unit!:
        try self.input.close()
        return self.output.close()

// Wraps a native WebSocket into a `WebSocket`.
export fn web_socket_from(raw: RawWebSocket) WebSocket:
    let subprotocol = msstd_websocket_subprotocol(raw.native)
    let other = RawWebSocket(msstd_websocket_share(raw.native))
    return WebSocket(
        input: stream[WebSocketMessage](WebSocketSource(raw)),
        output: writer[WebSocketMessage](WebSocketSink(other)),
        subprotocol: subprotocol
    )

// WebSocket message, timeout, TLS, and per-message compression settings.
export type WebSocketOptions:
    // Largest message accepted or sent, in bytes. Must be positive; none sets no limit.
    max_message_bytes: Int?
    // Time budget for connecting and completing the opening handshake. none waits indefinitely and a negative duration is rejected.
    timeout: Duration?
    // TLS settings for `wss` URLs: trusted roots, client identity, and protocols.
    tls: TlsOptions
    // When True, offers per-message compression during the handshake; it applies only if the peer agrees.
    compression: Bool

// Binds a UDP socket to `address` (`host:port`; port 0 picks a free port).
// A restricted network without listening permission, or an address outside its CIDRs, returns PermissionDenied.
export fn bind_datagram(address: String) DatagramSocket!:
    return ok(datagram_socket(try host_network().bind_datagram(address)))

// Resolves `address` (`host:port`) and opens a TCP connection to the first reachable permitted address.
// Returns PermissionDenied for names or addresses a restricted network disallows, Timeout when `timeout` elapses, and Failed when every address refuses.
export fn connect(address: String, timeout: Duration?) Connection!:
    return ok(connection(try host_network().connect(address, timeout)))

// Connects over TCP to `address` and completes a TLS handshake verifying the server certificate against the system roots for `server_name`, with at least TLS 1.2.
// An empty `server_name` returns InvalidInput, and `timeout` bounds the whole attempt.
export fn connect_tls(
    address: String,
    server_name: String,
    timeout: Duration?
) Connection!:
    return ok(connection(try host_network().connect_tls(address, server_name, timeout)))

// Connects over TCP to `address` and completes a TLS handshake using `options`, with at least TLS 1.2.
// Invalid options return InvalidInput, handshake and verification failures return Failed, and `timeout` bounds the whole attempt.
export fn connect_tls_config(
    address: String,
    options: TlsOptions,
    timeout: Duration?
) Connection!:
    return ok(connection(try host_network().connect_tls_config(address, options, timeout)))

// Connects to the Unix domain socket at `path`.
// Any restricted network returns PermissionDenied because Unix sockets bypass host and CIDR checks, and an empty path returns InvalidInput. `timeout` bounds the attempt.
export fn connect_unix(path: String, timeout: Duration?) Connection!:
    return ok(connection(try host_network().connect_unix(path, timeout)))

// Creates a reusable HTTP client with connection pooling that dials through this network, so its restrictions and resolver apply to every request and redirect.
// Invalid or negative options return InvalidInput. Closing the network closes the client.
export fn http_client(options: HttpClientOptions) HttpClient!:
    return host_network().http_client(options)

// Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
// A restricted network needs `allow_listen` and an IP-literal address inside its CIDRs, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
export fn listen(address: String) Listener!:
    return host_network().listen(address)

// Listens for TCP connections on `address` and completes a TLS handshake for each accepted connection, within `handshake_timeout` when supplied.
// `options` must hold a certificate and key, otherwise InvalidInput is returned.
export fn listen_tls(
    address: String,
    options: TlsOptions,
    handshake_timeout: Duration?
) Listener!:
    return host_network().listen_tls(address, options, handshake_timeout)

// Listens on a Unix domain socket at `path`.
// Any restricted network returns PermissionDenied, and an empty path returns InvalidInput.
export fn listen_unix(path: String) Listener!:
    return host_network().listen_unix(path)

/*
Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
More than `max_records` addresses returns LimitExceeded, `timeout` bounds the lookup, and a failed lookup returns Failed.
System-resolver lookups run on the runtime's blocking threads (`MS_POOL_THREADS`, default 4), at most half of them at once, while other tasks keep running.
*/
export fn lookup(name: String, max_records: Int?, timeout: Duration?) List[String]!:
    return host_network().lookup(name, max_records, timeout)

// Performs one buffered HTTP request and returns the status, headers, and complete body.
// Only `http` and `https` URLs without user info are accepted. Redirects are returned, not followed, and no cookies or proxy settings apply. A body over `max_response_bytes` returns LimitExceeded; error statuses are ordinary responses.
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

// Performs the same buffered request with a raw bytes body.
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

// Resolves the selected supported category, retaining it in each record.
export fn resolve_dns(
    name: String,
    kind: DnsKind,
    max_records: Int?,
    timeout: Duration?
) List[DnsRecord]!:
    return host_network().resolve(name, kind, max_records, timeout)

// Returns a derived network limited to the given host names and CIDR ranges.
// Names match case-insensitively without a trailing dot, and IP-literal hosts also match through `cidrs`. With `cidrs`, every resolved address must be inside one of them. `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A derived restriction can only narrow its parent, and closing the parent closes the child. Invalid host or CIDR text returns InvalidInput.
export fn restrict(
    hosts: List[String],
    cidrs: List[String],
    allow_listen: Bool
) Network!:
    return host_network().restrict(hosts, cidrs, allow_listen)

// Starts an HTTP server on `address` whose handler receives each request as an exchange: read the body and write the response incrementally, or use `read_body`, `reply`, and `buffered` from `@std/net/http.ms` for whole messages. Limits, timeouts, and TLS come from `options`.
// A request beyond `max_requests` concurrent requests is answered with 503, an oversized header block with 431, and a handler fault with 500. An address that cannot be bound returns Failed.
// Returns InvalidInput for invalid options (`cores` below 1 included). Close the server, or drop it, to stop it.
// `serve` binds a plain TCP listener and runs the accept loop as a promise. Each accepted connection becomes a promise of its own, which the runtime places on the least busy thread, where it stays; HTTP/1.1, HTTP/2 and the TLS handshake of `options.tls` run there. `handler` is built once and only read by every thread. `options.cores` limits the runtime to that many threads (none: every core).
// A handler is cancelled when its request times out or its client disconnects (an HTTP/1 connection closes or an HTTP/2 stream is reset): its waits end, `tasks.cancelled()` turns true, and its cleanups run. A client that half-closes its end after sending the request counts as disconnected.
// A faulting handler's frames release the heap values they own, as a cancelled handler's do. Return an error response for expected failures instead of faulting.
export fn serve(
    address: String,
    handler: fn(HttpExchange) Unit!,
    options: HttpServerOptions = HttpServerOptions()
) HttpServer!:
    if let cores = options.cores:
        if cores < 1:
            return error(Error("network: invalid input", kind: InvalidInput))

    let serving = try msstd_http_serving_new(address, options, handler)
    let bound = msstd_http_serving_address(serving)
    let listening = ServingHandle(serving: serving, listener: true)
    if let cores = options.cores:
        msrt_runtime_set_threads(cores)

    // The accept loop owns the serving; each connection it accepts owns another handle on it.
    let accepting = promise(fn: accept_loop(listening))
    return ok(HttpServer(accepting: accepting, bound: bound, stopped: false))

// A handle on a serving, which a promise owns and closes when it ends. The accept loop's handle also releases the listener; each connection's handle only gives its share back.
type ServingHandle:
    serving: NativeServing
    listener: Bool

impl Closeable for ServingHandle:
    var fn close() Unit!:
        if self.listener:
            msstd_http_serving_release(self.serving)
        return ok(unit)

// The connections of `serve`'s accept loop. Its close, which runs when the loop returns, is cancelled or faults, cancels all connections first so they drain side by side, then joins them.
type Accepting:
    connections: List[Promise[Unit]]

impl Closeable for Accepting:
    var fn close() Unit!:
        for connection in self.connections:
            let _ = connection.wait(timeout: 0.seconds)
        self.connections = []
        return ok(unit)

impl Accepting:
    // Drops the promises of connections that have ended.
    var fn sweep() Unit:
        var i = self.connections.length() - 1

        while i >= 0:
            if self.connections[i].done():
                self.connections.swap(i, self.connections.length() - 1)

                let _ = self.connections.pop()

            i -= 1

// Accepts until the listener fails. An accept that fails for lack of descriptors or memory pauses briefly instead of ending the server.
fn accept_loop(listening: ServingHandle) Unit!:
    var accepting = Accepting(connections: [])
    var sweep_at = 64

    while true:
        let accepted = msstd_http_serving_accept(listening.serving)

        if accepted.is_error():
            if accepted.err().kind == ErrorCategory.Closed:
                return ok(unit)

            sleep(50.milliseconds)
            continue

        let raw = accepted.get()
        let mine = ServingHandle(
            serving: msstd_http_serving_share(listening.serving), listener: false
        )
        accepting.connections.append(promise(fn: serve_connection(mine, raw)))

        if accepting.connections.length() >= sweep_at:
            accepting.sweep()
            sweep_at = 64
            if accepting.connections.length() * 2 > sweep_at:
                sweep_at = accepting.connections.length() * 2

    return ok(unit)

// Serves one accepted connection on the thread the runtime placed this promise on.
fn serve_connection(handle: ServingHandle, raw: Int) Unit!:
    msstd_http_serving_connect(handle.serving, raw)
    return ok(unit)

// Opens a WebSocket client connection to a `ws` or `wss` URL, sending the given headers and offering `subprotocols` in order.
// Handshake headers such as `Upgrade`, `Connection`, `Host`, and `Sec-WebSocket-*` cannot be set. A server that selects a subprotocol that was not offered fails the handshake. Failures are `Error` values.
export fn web_socket(
    url: String,
    headers: HttpHeaders,
    subprotocols: List[String],
    options: WebSocketOptions
) WebSocket!:
    return ok(web_socket_from(try host_network().web_socket(url, headers, subprotocols, options)))

// Returns a derived network that resolves names through the DNS server at `address`, an IP literal with port, instead of the system resolver.
// The address must be allowed by this network's restrictions, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
export fn with_resolver(address: String) Network!:
    return host_network().with_resolver(address)
