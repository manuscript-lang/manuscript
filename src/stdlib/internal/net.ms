import (
	Bytes from "@std/bytes.ms",
	DnsConfig from "@std/net/dns.ms",
	HttpHeaders,
	NativeConnection,
	NativeHttpClient,
	NativeListener,
	NativeTlsServer from "@std/net/http.ms",
	Cidr, DnsKind, DnsRecord, IpAddress from "@std/net/ip.ms",
	Datagram, NativeDatagramSocket, NativeScope from "@std/net/net.ms",
	CertificateInfo, TlsInfo, TlsOptions from "@std/net/tls.ms",
	NativeWebSocket,
	RawWebSocketMessage,
	WebSocketHandshake from "@std/net/websocket.ms",
	Duration, Timestamp from "@std/time.ms",
)

export extern fn msstd_net_ip_address_text(value: IpAddress) String

export extern fn msstd_net_ip_address_family(value: IpAddress) Bool

export extern fn msstd_net_cidr_text(value: Cidr) String

export extern fn msstd_net_contains_ip(cidr: Cidr, address: IpAddress) Bool!

export extern fn msstd_net_parse_cidr(text: String) Cidr!

export extern fn msstd_net_parse_ip(text: String) IpAddress!

export extern fn msstd_net_lookup(
	host: String,
	port: Int,
	timeout: Duration?,
) List[String]!

// The records of one kind that the DNS server at `server` (`ip:port`) holds for `name`;
// none when the name has none of that kind.
export extern fn msstd_dns_query(
	server: String,
	name: String,
	kind: DnsKind,
	timeout: Duration?,
) List[DnsRecord]?!

// The host's resolver settings.
export extern fn msstd_dns_config() DnsConfig!

export extern fn msstd_tls_parse_certificates(
	pem: String,
	max_certificates: Int?,
) List[CertificateInfo]!

export extern fn msstd_tls_verify_certificates(
	chain_pem: String,
	roots_pem: String,
	server_name: String,
	now: Timestamp,
) Void!

export extern fn msstd_conn_close(handle: NativeConnection) Void

export extern fn msstd_conn_share(handle: NativeConnection) NativeConnection

export extern fn msstd_conn_alias(handle: NativeConnection) NativeConnection

export extern fn msstd_conn_close_if_last(handle: NativeConnection) Void

export extern fn msstd_conn_local_address(handle: NativeConnection) String

export extern fn msstd_conn_peer_address(handle: NativeConnection) String

export extern fn msstd_conn_read(
	handle: NativeConnection,
	max_bytes: Int?,
	timeout: Duration?,
) Bytes?!

export extern fn msstd_conn_shutdown_write(handle: NativeConnection) Void!

export extern fn msstd_conn_start_tls(
	handle: NativeConnection,
	options: TlsOptions,
	timeout: Duration?,
) NativeConnection!

export extern fn msstd_conn_accept_tls(
	handle: NativeConnection,
	options: TlsOptions,
	timeout: Duration?,
) NativeConnection!

// The application protocol the handshake chose, such as `h2`; empty for none.
export extern fn msstd_conn_alpn(handle: NativeConnection) String

// A server TLS context built once, so each accepted connection reuses the parsed
// certificate: `accept_tls_with` is `accept_tls` on it.
export extern fn msstd_tls_server_new(options: TlsOptions) NativeTlsServer!

export extern fn msstd_tls_server_share(server: NativeTlsServer) NativeTlsServer

export extern fn msstd_conn_accept_tls_with(
	handle: NativeConnection,
	server: NativeTlsServer,
	timeout: Duration?,
) NativeConnection!

export extern fn msstd_conn_tls_info(handle: NativeConnection) TlsInfo?

export extern fn msstd_conn_write_bytes(
	handle: NativeConnection,
	data: Bytes,
	timeout: Duration?,
) Void!

export extern fn msstd_net_dial(
	address: String,
	server_name: String,
	has_tls: Bool,
	tls: TlsOptions,
	timeout: Duration?,
) NativeConnection!

export extern fn msstd_net_dial_unix(path: String) NativeConnection!

export extern fn msstd_net_listen(address: String) NativeListener!

export extern fn msstd_net_listen_unix(path: String) NativeListener!

export extern fn msstd_listener_accept(
	handle: NativeListener,
	timeout: Duration?,
) NativeConnection!

// Another handle on the same listener, for a promise that accepts on it.
export extern fn msstd_listener_share(handle: NativeListener) NativeListener

export extern fn msstd_listener_address(handle: NativeListener) String

export extern fn msstd_listener_close(handle: NativeListener) Void

export extern fn msstd_scope_share(scope: NativeScope) NativeScope

export extern fn msstd_scope_track_conn(
	scope: NativeScope,
	connection: NativeConnection,
) Bool

export extern fn msstd_scope_track_client(
	scope: NativeScope,
	client: NativeHttpClient,
) Bool

export extern fn msstd_scope_untrack_client(
	scope: NativeScope,
	client: NativeHttpClient,
) Bool

export extern fn msstd_scope_track_listener(
	scope: NativeScope,
	listener: NativeListener,
) Bool

export extern fn msstd_scope_new() NativeScope

export extern fn msstd_scope_child(scope: NativeScope) NativeScope

export extern fn msstd_scope_open(scope: NativeScope) Bool

export extern fn msstd_scope_close(scope: NativeScope) Void

export extern fn msstd_scope_track_dgram(
	scope: NativeScope,
	socket: NativeDatagramSocket,
) Bool

export extern fn msstd_dgram_bind(address: String) NativeDatagramSocket!

export extern fn msstd_dgram_address(handle: NativeDatagramSocket) String

export extern fn msstd_dgram_share(handle: NativeDatagramSocket) NativeDatagramSocket

export extern fn msstd_dgram_close_if_last(handle: NativeDatagramSocket) Void

export extern fn msstd_dgram_receive(
	handle: NativeDatagramSocket,
	max_bytes: Int?,
	timeout: Duration?,
) Datagram!

export extern fn msstd_dgram_send(
	handle: NativeDatagramSocket,
	data: Bytes,
	address: String,
	timeout: Duration?,
) Void!

// The server side of the opening handshake (src/runtime/include/ms_rt/xchg.h): checks
// the request and, when it is acceptable, fills `response` with the fields of the 101
// head. An upgrade the request does not ask for comes back as a refusal status, not an
// error.
export extern fn msstd_ws_handshake(
	method: String,
	host: String,
	tls: Bool,
	request: HttpHeaders,
	origins: List[String],
	subprotocols: List[String],
	response: HttpHeaders,
) WebSocketHandshake!

// The session over a connection taken from an exchange after its 101 head was sent.
export extern fn msstd_ws_serve(
	connection: NativeConnection,
	subprotocol: String,
	max_message_bytes: Int?,
) NativeWebSocket!

export extern fn msstd_websocket_close(handle: NativeWebSocket) Void

export extern fn msstd_websocket_share(handle: NativeWebSocket) NativeWebSocket

export extern fn msstd_websocket_close_if_last(handle: NativeWebSocket) Void

export extern fn msstd_websocket_ping(handle: NativeWebSocket, data: String) Void!

export extern fn msstd_websocket_ping_bytes(handle: NativeWebSocket, data: Bytes) Void!

export extern fn msstd_websocket_receive(handle: NativeWebSocket) RawWebSocketMessage?!

export extern fn msstd_websocket_send_bytes(
	handle: NativeWebSocket,
	data: Bytes,
	text: Bool,
) Void!

export extern fn msstd_websocket_subprotocol(handle: NativeWebSocket) String

export extern fn msstd_ws_connect(
	conn: NativeConnection,
	authority: String,
	target: String,
	headers: HttpHeaders,
	subprotocols: List[String],
	compression: Bool,
	max_message_bytes: Int?,
	timeout: Duration?,
) NativeWebSocket!
