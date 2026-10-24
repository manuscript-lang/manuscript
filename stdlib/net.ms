from "@std/bytes.ms" import Bytes
from "@std/http.ms" import ClientResponse
from "@std/time.ms" import Duration
from "@std/http.ms" import HttpClient
from "@std/http.ms" import HttpClientOptions
from "@std/http.ms" import HttpError
from "@std/http.ms" import HttpExchange
from "@std/http.ms" import HttpHeaders
from "@std/http.ms" import HttpMethod
from "@std/http.ms" import HttpRequest
from "@std/http.ms" import HttpResponse
from "@std/http.ms" import HttpServer
from "@std/http.ms" import HttpServerOptions
from "@std/io.ms" import IoError
from "@std/time.ms" import Timestamp

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
    def close() -> Unit
    # Returns this end's address as `host:port` text, with IPv6 hosts in brackets; for Unix sockets it is the socket path.
    def local_address() -> String
    # Returns the remote end's address as `host:port` text, with IPv6 hosts in brackets.
    def peer_address() -> String
    # Returns a positive chunk or none at EOF; local timeout uses IoError.Failed, not NetworkError.Timeout.
    def read(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[Optional[Bytes], IoError]
    # Half-closes the connection so the peer sees end of stream, while this side can keep reading.
    # Returns Unsupported for stream kinds that cannot half-close, and Closed on a closed connection.
    def shutdown_write() -> Result[Unit, NetworkError]
    # Returns the negotiated TLS version, cipher suite, protocol, and peer certificates.
    # A connection that is not TLS returns InvalidInput.
    def tls_info() -> Result[TlsInfo, TlsError]
    # Writes all bytes on success; failure can leave a prefix. Local timeout uses IoError.Failed.
    def write(data: String, timeout: Optional[Duration] = none) -> Result[Unit, IoError]
    # Writes raw bytes with the same rules as write.
    def write_bytes(
        data: Bytes,
        timeout: Optional[Duration] = none
    ) -> Result[Unit, IoError]

# One datagram and the address from which it was received.
export type Datagram:
    # The payload bytes of this datagram, never longer than the receive call's `max_bytes`.
    data: Bytes
    # Native host:port text, with bracketed IPv6 addresses.
    sender: String

# A connectionless socket for sending and receiving datagrams.
export interface DatagramSocket:
    # Returns the bound local address as `host:port` text, which reveals the port chosen when binding port 0.
    def address() -> String
    # Closes the socket, interrupting calls in progress, and waits for them to stop.
    # Safe to call repeatedly.
    def close() -> Unit
    # Waits for one datagram and returns its bytes with the sender's address. `max_bytes` is 1 through 65535 and defaults to 65535.
    # A larger datagram returns LimitExceeded and is discarded. A timeout returns Timeout and a closed socket returns Closed.
    def receive(
        max_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[Datagram, NetworkError]
    # Sends `data` as a single datagram to `address` (`host:port`), resolving a host name with the network's resolver.
    # The network's restrictions apply to both the name and the resolved address. A short send returns Failed; a timeout returns Timeout.
    def send(
        data: String,
        address: String,
        timeout: Optional[Duration] = none
    ) -> Result[Unit, NetworkError]
    # Sends raw bytes as a single datagram with the same rules as send.
    def send_bytes(
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

impl DnsKind:
    # Returns the uppercase wire category.
    def text() -> String: ...

# Numeric address families reported by IP values and host interfaces.
export type IpFamily:
    # A four-byte numeric address.
    case IPv4
    # A sixteen-byte numeric address.
    case IPv6

impl IpFamily:
    # Returns IPv4 or IPv6.
    def text() -> String: ...

# A validated numeric IPv4/IPv6 address without a port or zone.
export type IpAddress: ...

impl IpAddress:
    # Returns canonical text; mapped IPv6 input is normalized to IPv4.
    def text() -> String: ...

    # Returns the normalized address family.
    def family() -> IpFamily: ...

# A validated, masked numeric CIDR range.
export type Cidr: ...

impl Cidr:
    # Returns the canonical masked prefix without reparsing.
    def text() -> String: ...

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
    def accept(timeout: Optional[Duration] = none) -> Result[Connection, NetworkError]
    # Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.
    def address() -> String
    # Stops accepting, interrupts a pending `accept`, and waits for it to stop.
    # Safe to call repeatedly; connections already accepted stay open.
    def close() -> Unit

# Reports whether an IP address belongs to a CIDR range.
export def contains_ip(cidr: Cidr, address: IpAddress) -> Result[Bool, NetworkError]: ...

# Validates and canonicalizes an IPv4 or IPv6 CIDR range.
export def parse_cidr(text: String) -> Result[Cidr, NetworkError]: ...

# Validates and canonicalizes an IPv4 or IPv6 address.
export def parse_ip(text: String) -> Result[IpAddress, NetworkError]: ...

impl Error for NetworkError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `network: <reason>`.
    def message() -> String: ...

# Network, DNS, HTTP, and WebSocket operations for the current host.
export interface Network:
    # Binds a UDP socket to `address` (`host:port`; port 0 picks a free port).
    # A restricted network without listening permission, or an address outside its CIDRs, returns PermissionDenied.
    def bind_datagram(address: String) -> Result[DatagramSocket, NetworkError]
    # Cancels in-flight calls and closes every connection, listener, socket, HTTP client, and server this network opened, including those of derived networks.
    # Safe to call repeatedly. A request handler of a server on this network cannot close it and faults.
    def close() -> Unit
    # Resolves `address` (`host:port`) and opens a TCP connection to the first reachable permitted address.
    # Returns PermissionDenied for names or addresses a restricted network disallows, Timeout when `timeout` elapses, and Failed when every address refuses.
    def connect(
        address: String,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    # Connects over TCP to `address` and completes a TLS handshake verifying the server certificate against the system roots for `server_name`, with at least TLS 1.2.
    # An empty `server_name` returns InvalidInput, and `timeout` bounds the whole attempt.
    def connect_tls(
        address: String,
        server_name: String,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    # Connects over TCP to `address` and completes a TLS handshake using `options`, with at least TLS 1.2.
    # Invalid options return InvalidInput, handshake and verification failures return Failed, and `timeout` bounds the whole attempt.
    def connect_tls_config(
        address: String,
        options: TlsOptions,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    # Connects to the Unix domain socket at `path`.
    # Any restricted network returns PermissionDenied because Unix sockets bypass host and CIDR checks. `timeout` bounds the attempt.
    def connect_unix(
        path: String,
        timeout: Optional[Duration] = none
    ) -> Result[Connection, NetworkError]
    # Creates a reusable HTTP client with connection pooling that dials through this network, so its restrictions and resolver apply to every request and redirect.
    # Invalid or negative options return InvalidInput. Closing the network closes the client.
    def http_client(options: HttpClientOptions) -> Result[HttpClient, HttpError]
    # Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
    # A restricted network needs `allow_listen` and an IP-literal address inside its CIDRs, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
    def listen(address: String) -> Result[Listener, NetworkError]
    # Listens for TCP connections on `address` and completes a TLS handshake for each accepted connection, within `handshake_timeout` when supplied.
    # `options` must hold a certificate and key, otherwise InvalidInput is returned.
    def listen_tls(
        address: String,
        options: TlsOptions,
        handshake_timeout: Optional[Duration] = none
    ) -> Result[Listener, NetworkError]
    # Listens on a Unix domain socket at `path`.
    # Any restricted network returns PermissionDenied.
    def listen_unix(path: String) -> Result[Listener, NetworkError]
    # Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
    # More than `max_records` addresses returns LimitExceeded, `timeout` bounds the lookup, and a failed lookup returns Failed.
    # System-resolver lookups run on the runtime's blocking threads (`MS_POOL_THREADS`, default 4), at most half of them at once, while other tasks keep running.
    def lookup(
        name: String,
        max_records: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[List[String], NetworkError]
    # Performs one buffered HTTP request and returns the status, headers, and complete body.
    # Only `http` and `https` URLs without user info are accepted. Redirects are returned, not followed, and no cookies or proxy settings apply. A body over `max_response_bytes` returns LimitExceeded; error statuses are ordinary responses.
    def request(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: String = "",
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[ClientResponse, HttpError]
    # Performs the same buffered request with a raw bytes body.
    def request_bytes(
        method: HttpMethod,
        url: String,
        headers: HttpHeaders,
        body: Bytes = "".to_bytes(),
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[ClientResponse, HttpError]
    # Resolves the selected supported category, retaining it in each record.
    def resolve(
        name: String,
        kind: DnsKind,
        max_records: Optional[Int] = none,
        timeout: Optional[Duration] = none
    ) -> Result[List[DnsRecord], NetworkError]
    # Returns a derived network limited to the given host names and CIDR ranges.
    # Names match case-insensitively without a trailing dot, and IP-literal hosts also match through `cidrs`. With `cidrs`, every resolved address must be inside one of them. `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A derived restriction can only narrow its parent, and closing the parent closes the child. Invalid host or CIDR text returns InvalidInput.
    def restrict(
        hosts: List[String],
        cidrs: List[String],
        allow_listen: Bool
    ) -> Result[Network, NetworkError]
    # Starts an HTTP server on `address` that calls `handler` with each fully buffered request and sends the returned response.
    # A request beyond `limit` concurrent requests is answered with 503, a request header block over 1 MiB with 431, an oversized request body with 413, and a handler fault with 500. An address that cannot be bound returns IoError.Unavailable.
    def serve(
        address: String,
        handler: Callable[[HttpRequest], HttpResponse],
        max_requests: Optional[Int] = none,
        max_body_bytes: Optional[Int] = none,
        max_response_bytes: Optional[Int] = none,
        timeout: Optional[Duration] = none,
        grace: Optional[Duration] = none
    ) -> Result[HttpServer, IoError]
    # Starts an HTTP server on `address` whose handler receives each request as a streaming exchange. Limits, timeouts, and TLS come from `options`.
    # Returns PermissionDenied when a restricted network disallows listening, and InvalidInput for invalid options. Close the server to stop it.
    def serve_stream(
        address: String,
        handler: Callable[[HttpExchange], Result[Unit, HttpError]],
        options: HttpServerOptions
    ) -> Result[HttpServer, HttpError]
    # Opens a WebSocket client connection to a `ws` or `wss` URL, sending the given headers and offering `subprotocols` in order.
    # Handshake headers such as `Upgrade`, `Connection`, `Host`, and `Sec-WebSocket-*` cannot be set. Failures use WebSocketError.
    def web_socket(
        url: String,
        headers: HttpHeaders,
        subprotocols: List[String],
        options: WebSocketOptions
    ) -> Result[WebSocket, WebSocketError]
    # Returns a derived network that resolves names through the DNS server at `address`, an IP literal with port, instead of the system resolver.
    # The address must be allowed by this network's restrictions, otherwise PermissionDenied is returned. An address that is not an IP literal with a port returns InvalidInput.
    def with_resolver(address: String) -> Result[Network, NetworkError]

# Returns network operations for the current host.
export def network() -> Network: ...

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
    # True when the peer's certificate chain was verified against the configured roots; false when no peer chain was verified.
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
    # Servers only: when true, a client must present a certificate that verifies against `roots_pem`. Setting it on a client configuration is rejected.
    require_client_certificate: Bool

# Parses PEM certificates and optionally limits the number returned.
export def parse_certificates(
    pem: String,
    max_certificates: Optional[Int] = none
) -> Result[List[CertificateInfo], TlsError]: ...

# Verifies a PEM certificate chain against roots, name constraints, and the supplied time.
export def verify_certificates(
    chain_pem: String,
    roots_pem: String,
    server_name: String,
    now: Timestamp
) -> Result[Unit, TlsError]: ...

impl Error for TlsError:
    # Returns the fixed diagnostic `TLS: <reason>`, such as `TLS: authentication failed`, without echoing certificate text.
    def message() -> String: ...

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
export def decode_component(text: String) -> Result[String, UrlError]: ...

# Percent-encodes one URL component using UTF-8 bytes.
export def encode_component(text: String) -> String: ...

# Formats URL components as an absolute hierarchical URL.
# Missing or malformed schemes and hostless relative paths return InvalidInput, as do other invalid components.
export def format(value: Url) -> Result[String, UrlError]: ...

# Encodes query entries as a query string.
export def format_query(entries: List[QueryEntry]) -> String: ...

# Parses an absolute URL into its components.
export def parse(text: String) -> Result[Url, UrlError]: ...

# Parses a query string, preserving duplicate keys and their input order.
export def parse_query(
    text: String,
    max_entries: Optional[Int] = none
) -> Result[List[QueryEntry], UrlError]: ...

# Resolves a relative reference against a base URL.
export def resolve(base: Url, reference: String) -> Result[Url, UrlError]: ...

impl Error for UrlError:
    # Returns a URL-prefixed diagnostic without echoing addresses, query values or credentials.
    def message() -> String: ...

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

# A WebSocket connection. Send and receive byte messages with an explicit text flag.
export interface WebSocket:
    # Sends a normal-closure frame, waiting at most about 100 ms to write it, then closes the connection and waits for in-flight calls to stop.
    # Safe to call repeatedly; later calls wait for the first.
    def close() -> Unit
    # Sends a ping frame carrying `data`, which must be at most 125 bytes, with a one-second write deadline.
    # It does not wait for the pong. Returns Closed on a closed socket.
    def ping(data: String) -> Result[Unit, WebSocketError]
    # Sends a ping frame carrying raw bytes, with the same limits and deadline as ping.
    def ping_bytes(data: Bytes) -> Result[Unit, WebSocketError]
    # Waits for the next complete message and returns it, or none once the peer closes normally.
    # A larger message returns LimitExceeded and a malformed text message InvalidData; after any receive failure the connection is closed. One receive runs at a time, and others wait their turn.
    def receive() -> Result[Optional[WebSocketMessage], WebSocketError]
    # Sends `data` as one text message; a payload over `max_message_bytes` returns LimitExceeded. One send runs at a time.
    def send(data: String) -> Result[Unit, WebSocketError]
    # Sends `data` as one message, a text frame when `text` is true and a binary frame (the default) otherwise.
    # Text must be valid UTF-8 or the call returns InvalidData, and a payload over `max_message_bytes` returns LimitExceeded. One send runs at a time.
    def send_bytes(data: Bytes, text: Bool = False) -> Result[Unit, WebSocketError]
    # Returns the subprotocol the server selected during the handshake, or an empty string when none was negotiated.
    def subprotocol() -> String

# A received message and whether its payload is UTF-8 text.
export type WebSocketMessage:
    # The message payload bytes; for a text message they are the UTF-8 encoding of the text.
    data: Bytes
    # True when the peer sent a text frame, which guarantees `data` is valid UTF-8; false for a binary frame.
    text: Bool

# WebSocket message, timeout, TLS, and per-message compression settings.
export type WebSocketOptions:
    # Largest message accepted or sent, in bytes. Must be positive; none sets no limit.
    max_message_bytes: Optional[Int] = none
    # Time budget for connecting and completing the opening handshake. none waits indefinitely and a negative duration is rejected.
    timeout: Optional[Duration] = none
    # TLS settings for `wss` URLs: trusted roots, client identity, and protocols.
    tls: TlsOptions
    # When true, offers per-message compression during the handshake; it applies only if the peer agrees.
    compression: Bool

impl Error for WebSocketError:
    # Returns the `Failed` text verbatim, and otherwise the fixed diagnostic `WebSocket: <reason>`.
    def message() -> String: ...
