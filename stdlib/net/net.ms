import (
	Bytes from "@std/bytes.ms",
	Placement,
	Promise,
	PromiseOptions,
	complete,
	deferred,
	promise from "@std/concurrency/promise.ms",
	Closeable, Writable from "@std/core.ms",
	Pipe, ReadStream, Sink, Source, WriteStream, pipe from "@std/io/io.ms",
	dns_lookup, dns_resolve from "@std/net/dns.ms",
	ClientResponse,
	HttpClient,
	HttpClientOptions,
	HttpExchange,
	HttpHeaders,
	HttpMethod,
	HttpServer,
	HttpServerOptions,
	NativeConnection,
	NativeListener,
	headers,
	open_client from "@std/net/http.ms",
	Cidr, DnsKind, DnsRecord, IpAddress, parse_ip from "@std/net/ip.ms",
	Policy,
	address_allowed,
	host_allowed,
	listen_allowed,
	narrow,
	unix_allowed,
	unrestricted from "@std/net/policy.ms",
	start_server from "@std/net/serve.ms",
	TlsInfo, TlsOptions from "@std/net/tls.ms",
	parse from "@std/net/url.ms",
	WebSocket, WebSocketOptions, web_socket_from from "@std/net/websocket.ms",
	Duration, Instant, Timestamp, monotonic, nanoseconds, sleep from "@std/time.ms",

	msstd_conn_accept_tls,
	msstd_conn_alias,
	msstd_conn_close,
	msstd_conn_close_if_last,
	msstd_conn_local_address,
	msstd_conn_peer_address,
	msstd_conn_read,
	msstd_conn_share,
	msstd_conn_shutdown_write,
	msstd_conn_start_tls,
	msstd_conn_tls_info,
	msstd_conn_write_bytes,
	msstd_dgram_address,
	msstd_dgram_bind,
	msstd_dgram_close_if_last,
	msstd_dgram_receive,
	msstd_dgram_send,
	msstd_dgram_share,
	msstd_listener_accept,
	msstd_listener_address,
	msstd_listener_close,
	msstd_listener_share,
	msstd_net_dial,
	msstd_net_dial_unix,
	msstd_net_listen,
	msstd_net_listen_unix,
	msstd_net_lookup,
	msstd_scope_child,
	msstd_scope_close,
	msstd_scope_new,
	msstd_scope_open,
	msstd_scope_share,
	msstd_scope_track_client,
	msstd_scope_track_conn,
	msstd_scope_track_dgram,
	msstd_scope_track_listener,
	msstd_scope_untrack_client,
	msstd_ws_connect from "@std/internal/net.ms",
)

type ConnectionSource:
	native: NativeConnection

// Waits for the next chunk; none at the end of the stream.
fn var ConnectionSource.next() Bytes?!:
	return msstd_conn_read(self.native, none, none)

// Closes the socket when the output end is already closed.
fn move ConnectionSource.close() Void!:
	msstd_conn_close_if_last(self.native)

type ConnectionSink:
	native: NativeConnection

fn var ConnectionSink.write(move value: Bytes) Void!:
	return msstd_conn_write_bytes(self.native, value, none)

fn var ConnectionSink.flush() Void!:
	return ok()

// Half-closes the connection so the peer sees the end of the stream; the socket
// closes once the input is closed too.
fn move ConnectionSink.close() Void!:
	void msstd_conn_shutdown_write(self.native)
	msstd_conn_close_if_last(self.native)

// What is known about a connection, available after its streams are moved elsewhere.
export type ConnectionInfo:
	// This end's address as `host:port` text, with IPv6 hosts in brackets; for Unix
	// sockets it is the socket path.
	local_address: String
	// The remote end's address as `host:port` text, with IPv6 hosts in brackets.
	peer_address: String
	// The negotiated TLS version, cipher suite, protocol, and peer certificates; none
	// when the connection is not TLS.
	tls: TlsInfo?

// Returns the negotiated TLS version, cipher suite, protocol, and peer
// certificates. A connection that is not TLS returns EINVAL.
fn ConnectionInfo.tls_info() TlsInfo!:
	if info := self.tls: return ok(info.clone())
	return error(Error("network: invalid input", kind: "EINVAL"))

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
	// The runtime handle that `start_tls` and `accept_tls` upgrade.
	native: NativeConnection

// Closes both streams, and with them the socket.
fn move Connection.close() Void!:
	self.input.close()?
	return self.output.close()

// Wraps a native socket into a `Connection`.
fn connection(native: NativeConnection) Connection:
	local := msstd_conn_local_address(native)
	peer := msstd_conn_peer_address(native)
	var tls: TlsInfo? = none
	if found := msstd_conn_tls_info(native): tls = found

	other := msstd_conn_share(native)
	upgradable := msstd_conn_alias(native)
	return Connection(
		input: ReadStream[Bytes](ConnectionSource(native)),
		output: WriteStream[Bytes](ConnectionSink(other)),
		info: ConnectionInfo(local, peer, tls),
		native: upgradable,
	)

/*
Upgrades a plain TCP connection to TLS in place, as a protocol's STARTTLS step does (Postgres `SSLRequest`, SMTP and IMAP
`STARTTLS`). It runs the client handshake on the same socket and returns the TLS connection. The `plain` argument is
consumed: it is closed without closing the socket, and the returned connection owns the socket. Use the returned
connection from here on.

The connection must be plain and idle: no read or write may be waiting on it, and the peer must send no application
bytes before it agrees to TLS. `options` is read as for `connect`: `server_name` is required and verified against
`roots_pem` (the system roots when empty), with at least TLS 1.2. `timeout` bounds the handshake. EINVAL is returned when
the connection is already TLS, is busy, or `options` is invalid, with the connection left usable; EBADF when it is
closed; ETIMEDOUT when `timeout` elapses; and EIO when the handshake or verification fails, which consumes the
connection.
*/
export fn start_tls(
	var plain: Connection,
	options: TlsOptions = TlsOptions(),
	timeout: Duration? = none,
) Connection!:
	if options.server_name.is_empty():
		return error(Error("network: invalid input", kind: "EINVAL"))

	upgraded := msstd_conn_start_tls(plain.native, options, timeout)?
	return ok(connection(upgraded))

// Upgrades a plain TCP connection to TLS in place on the server side: it accepts the
// client's handshake with the certificate and key in `options`, then returns the TLS
// connection, consuming `plain` as `start_tls` does. `options` must hold a certificate
// and key, otherwise EINVAL is returned; the other errors match `start_tls`.
export fn accept_tls(
	var plain: Connection,
	options: TlsOptions = TlsOptions(),
	timeout: Duration? = none,
) Connection!:
	upgraded := msstd_conn_accept_tls(plain.native, options, timeout)?
	return ok(connection(upgraded))

// One datagram. When received, `address` is where it came from; when written, where it
// goes.
export type Datagram:
	// The payload bytes of this datagram, at most 65535 bytes.
	data: Bytes
	// The address as `host:port` text, with IPv6 hosts in brackets.
	address: String

// The runtime handle behind a `DatagramSocket`.
export extern type NativeDatagramSocket

type DatagramSource:
	native: NativeDatagramSocket

// Waits for one datagram, at most 65535 bytes; a larger one is an error of kind
// `EOVERFLOW` and is discarded.
fn var DatagramSource.next() Datagram?!:
	return ok(msstd_dgram_receive(self.native, none, none)?)

fn move DatagramSource.close() Void!:
	msstd_dgram_close_if_last(self.native)

type DatagramSink:
	native: NativeDatagramSocket
	policy: Policy

// Sends `value.data` as one datagram to `value.address`, resolving a host name with
// the network's resolver.
fn var DatagramSink.write(move value: Datagram) Void!:
	target := permitted_address(self.policy, value.address, none)?
	return msstd_dgram_send(self.native, value.data, target, none)

fn var DatagramSink.flush() Void!:
	return ok()

fn move DatagramSink.close() Void!:
	msstd_dgram_close_if_last(self.native)

// A connectionless socket for sending and receiving datagrams. Closing it closes both
// streams.
export type DatagramSocket:
	// Datagrams received, with the sender's address.
	input: ReadStream[Datagram]
	// Datagrams to send; each carries its destination.
	output: WriteStream[Datagram]
	// The bound local address as `host:port` text, which reveals the port chosen when
	// binding port 0.
	address: String

// Closes both streams, and with them the socket.
fn move DatagramSocket.close() Void!:
	self.input.close()?
	return self.output.close()

fn datagram_socket(native: NativeDatagramSocket, policy: Policy) DatagramSocket:
	address := msstd_dgram_address(native)
	other := msstd_dgram_share(native)
	return DatagramSocket(
		input: ReadStream[Datagram](DatagramSource(native)),
		output: WriteStream[Datagram](DatagramSink(other, policy)),
		address: address,
	)

// A listening socket that accepts incoming connections. Several tasks may call `accept`
// on one listener (an accept pool); each incoming connection goes to exactly one of
// them.
export opaque type Listener:
	// The runtime handle; it is released by `close` and owned by this value.
	native: NativeListener
	// The scope of the network that opened this listener, which tracks its connections.
	scope: NativeScope
	// The TLS settings every accepted connection is upgraded with, none for plain TCP.
	tls: TlsOptions?
	// The time budget of each TLS handshake.
	handshake: Duration?

// Stops accepting, interrupts a pending `accept`, and waits for it to stop.
// Safe to call repeatedly; connections already accepted stay open.
fn move Listener.close() Void!:
	msstd_listener_close(self.native)

// Starts waiting for the next incoming connection and returns its promise. A
// timeout gives ETIMEDOUT and a closed listener gives EBADF from `wait`. On a TLS
// listener the handshake completes before the connection is returned; a failed
// handshake drops that connection and gives EIO.
fn Listener.accept(timeout: Duration? = none) Promise[Connection]:
	native := msstd_listener_share(self.native)
	tls := self.tls.clone()
	scope := msstd_scope_share(self.scope)
	handshake := self.handshake.clone()
	return promise(
		fn: accepted(native, scope, tls, handshake, timeout),
		options: PromiseOptions(placement: Placement.Here)
	)

// Starts waiting for the next incoming connection without binding it to a thread, and
// returns its promise. A timeout gives ETIMEDOUT and a closed listener gives EBADF from
// `wait`, as for `accept`. A TLS listener gives EINVAL: its handshake belongs to the
// accepting thread.
fn Listener.accept_pending(timeout: Duration? = none) Promise[PendingConnection]:
	native := msstd_listener_share(self.native)
	return promise(
		fn: accepted_pending(native, timeout),
		options: PromiseOptions(placement: Placement.Here)
	)

// Returns the bound local address as `host:port` text, which reveals the port
// chosen when listening on port 0.
fn Listener.address() String:
	return msstd_listener_address(self.native)

// The work of `accept`, on its own handle on the listener.
fn accepted(
	native: NativeListener,
	scope: NativeScope,
	tls: TlsOptions?,
	handshake: Duration?,
	timeout: Duration?,
) Connection!:
	raw := msstd_listener_accept(native, timeout)?

	if options := tls:
		secured := msstd_conn_accept_tls(raw, options, handshake)?
		return tracked(scope, secured)

	return tracked(scope, raw)

// Registers an accepted connection with its network's scope.
fn tracked(scope: NativeScope, native: NativeConnection) Connection!:
	if not msstd_scope_track_conn(scope, native): return error(closed_error())
	return ok(connection(native))

fn accepted_pending(native: NativeListener, timeout: Duration?) PendingConnection!:
	return ok(
		PendingConnection(
			native: msstd_listener_accept(native, timeout)?,
			taken: false,
		)
	)

// An accepted connection that no thread has taken yet. A connection belongs to the
// thread that uses it, so accepting and using it are two steps: the listener's thread
// accepts, and whichever thread should serve the connection calls `adopt`. Move it into
// a promise placed with `Placement.Spread` to serve connections on every core, as
// `serve` does for HTTP. Closing it without adopting closes the socket.
export opaque type PendingConnection:
	// The accepted socket.
	native: NativeConnection
	// Whether it was adopted or closed.
	taken: Bool

// Closes the socket unless it was adopted. Safe to call repeatedly.
fn var PendingConnection.close() Void!:
	if not self.taken:
		self.taken = true
		msstd_conn_close(self.native)

// Turns the pending connection into a `Connection` owned by the calling thread.
// Adopting twice returns EBADF.
fn var PendingConnection.adopt() Connection!:
	if self.taken: return error(closed_error())

	self.taken = true
	return ok(connection(msstd_conn_share(self.native)))

// A host and port split from `host:port` text.
type HostPort:
	host: String
	port: Int

fn split_host_port(address: String) HostPort?:
	if parts := address.rsplit_once(":"):
		port := parts.after.parse_int()
		if not port.is_some() or port.get() < 0 or port.get() > 65535: return none

		var host = parts.before.clone()

		if host.starts_with("[") and host.ends_with("]"):
			host = host.slice(1, -1)
		else if host.contains(":"):
			return none

		return HostPort(host: host, port: port.get())

	return none

fn literal_address(host: String, port: Int) String:
	if host.contains(":"): return "[" + host + "]:" + port.to_string()
	return host + ":" + port.to_string()

fn invalid_address() Error:
	return Error("network: invalid input", kind: "EINVAL")

fn closed_error() Error:
	return Error("network: resource is closed", kind: "EBADF")

fn denied() Error:
	return Error("network: permission denied", kind: "EACCES")

// The literal address a datagram may be sent to: the policy checks the host, a name is
// resolved, and the first address the policy allows wins.
fn permitted_address(policy: Policy, address: String, timeout: Duration?) String!:
	found := split_host_port(address)
	if not found.is_some(): return error(invalid_address())

	target := found.get()
	if not host_allowed(policy, target.host): return error(denied())

	if parse_ip(target.host).is_ok():
		if not address_allowed(policy, target.host): return error(denied())
		return ok(literal_address(target.host, target.port))

	for text in msstd_net_lookup(target.host, target.port, timeout)?:
		ip := split_host_port(text)
		if ip.is_some() and address_allowed(policy, ip.get().host): return ok(text)

	return error(denied())

// Sends one request on `client` and reads the whole response.
fn buffered(
	client: HttpClient,
	method: HttpMethod,
	url: String,
	headers: HttpHeaders,
	body: Bytes,
	max_bytes: Int?,
	timeout: Duration?,
) ClientResponse!:
	raw := client.request_raw(method, url, headers, body, max_bytes, timeout)?
	head := raw.metadata()
	data := raw.read_all()?
	return ok(ClientResponse(head: head, body: data))

// What a `Network` closes: the sockets opened through it and the networks derived from
// it.
export extern type NativeScope

// A set of network permissions and a resolver for the connections, listeners, sockets,
// and HTTP clients opened through it. The host network that the module-level functions
// use is unrestricted; `restrict` derives a narrower one.
export opaque type Network:
	// The host names and address ranges this network allows.
	policy: Policy
	// The DNS server (`ip:port`) that names resolve through; empty for the system
	// resolver.
	resolver: String
	// The sockets and derived networks that `close` closes.
	scope: NativeScope

// Binds a UDP socket to `address` (`host:port`; port 0 picks a free port). A
// restricted network without listening permission, or an address outside its CIDRs,
// returns EACCES.
fn Network.bind_datagram(address: String) DatagramSocket!:
	if not msstd_scope_open(self.scope): return error(closed_error())

	var failure = denied()

	for target in self.bind_targets(address)?:
		bound := msstd_dgram_bind(target)

		if bound.is_error():
			failure = bound.err()
			continue

		native := bound.get()
		if not msstd_scope_track_dgram(self.scope, native): return error(closed_error())

		return ok(datagram_socket(native, self.policy.clone()))

	return error(failure)

// Cancels in-flight calls and closes every connection, listener, socket, HTTP
// client, and server this network opened, including those of derived networks. Safe
// to call repeatedly. A request handler of a server on this network cannot close it
// and faults.
fn Network.close() Void:
	msstd_scope_close(self.scope)

// Resolves `address` (`host:port`) and opens a TCP connection to the first
// reachable permitted address, completing a TLS handshake with `tls` when given.
// The wait happens in the calling task; the module-level `connect` starts the same
// work as a promise. Returns EACCES for names or addresses a restricted network
// disallows, ETIMEDOUT when `timeout` elapses, and EIO when every address refuses
// or the handshake or verification fails.
// `tls` verifies the server certificate against `tls.roots_pem` (the system roots when
// empty) for `tls.server_name`, with at least TLS 1.2; an empty `server_name` or
// invalid options return EINVAL. `timeout` bounds the whole attempt.
fn Network.connect(
	address: String,
	tls: TlsOptions? = none,
	timeout: Duration? = none,
) Connection!:
	native := self.dial(address, tls, timeout)?
	return ok(connection(native))

// The tracked native connection behind `connect`; `web_socket` runs its handshake on
// one.
fn Network.dial(address: String, tls: TlsOptions?, timeout: Duration?) NativeConnection!:
	if not msstd_scope_open(self.scope): return error(closed_error())

	found := split_host_port(address)
	if not found.is_some(): return error(invalid_address())

	var options = TlsOptions()

	if given := tls:
		if given.server_name.is_empty(): return error(invalid_address())

		options = given.clone()

	target := found.get()
	if not host_allowed(self.policy, target.host): return error(denied())

	started := monotonic()
	var refused = denied()

	for ip in self.addresses_of(target.host, timeout.clone())?:
		if not address_allowed(self.policy, ip): continue

		left := remaining(started, timeout.clone())?
		dialed := msstd_net_dial(
			literal_address(ip, target.port),
			"",
			tls.is_some(),
			options,
			left,
		)

		if dialed.is_error():
			refused = dialed.err()
			continue

		native := dialed.get()
		if not msstd_scope_track_conn(self.scope, native): return error(closed_error())

		return ok(native)

	return error(refused)

// The addresses a host name stands for, as IP text: a literal is itself, a name goes
// through this network's resolver.
fn Network.addresses_of(host: String, timeout: Duration?) List[String]!:
	if parse_ip(host).is_ok(): return ok([host.clone()])
	return self.lookup(host, DnsOptions(timeout: timeout))

// The time left of `timeout` since `started`, or ETIMEDOUT when none is.
// Connects to the Unix domain socket at `path`. Any restricted network returns
// EACCES because Unix sockets bypass host and CIDR checks, and an empty path
// returns EINVAL.
fn Network.connect_unix(path: String, timeout: Duration? = none) Connection!:
	if not msstd_scope_open(self.scope): return error(closed_error())
	if not unix_allowed(self.policy): return error(denied())
	if path.is_empty(): return error(invalid_address())

	native := msstd_net_dial_unix(path)?
	if not msstd_scope_track_conn(self.scope, native): return error(closed_error())

	return ok(connection(native))

// Creates a reusable HTTP client with connection pooling that dials through this
// network, so its restrictions and resolver apply to every request and redirect.
// Invalid or negative options return EINVAL. Closing the network closes the client.
fn Network.http_client(options: HttpClientOptions = HttpClientOptions()) HttpClient!:
	if not msstd_scope_open(self.scope): return error(closed_error())

	client := open_client(self.policy, options, self.resolver.clone())?
	if not msstd_scope_track_client(self.scope, client.native): return error(
		closed_error()
	)

	return ok(client)

// Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
// A restricted network needs `allow_listen` and an IP-literal address inside its
// CIDRs, otherwise EACCES is returned. An address that is not an IP literal with a
// port returns EINVAL.
fn Network.listen(address: String) Listener!:
	return self.listening(self.listen_native(address)?, none, none)

// Binds a TCP listener on the first address the policy allows.
fn Network.listen_native(address: String) NativeListener!:
	if not msstd_scope_open(self.scope): return error(closed_error())

	var failure = denied()

	for target in self.bind_targets(address)?:
		opened := msstd_net_listen(target)

		if opened.is_error():
			failure = opened.err()
			continue

		return ok(opened.get())

	return error(failure)

// Wraps a bound listener and registers it with this network's scope.
fn Network.listening(
	native: NativeListener,
	tls: TlsOptions?,
	handshake: Duration?,
) Listener!:
	if not msstd_scope_track_listener(self.scope, native): return error(closed_error())
	return ok(
		Listener(
			native: native,
			tls: tls,
			handshake: handshake,
			scope: msstd_scope_share(self.scope),
		)
	)

// Listens for TCP connections on `address` and completes a TLS handshake for each
// accepted connection, within `timeout` when supplied.
// `options` must hold a certificate and key, otherwise EINVAL is returned.
fn Network.listen_tls(
	address: String,
	options: TlsOptions,
	timeout: Duration? = none,
) Listener!:
	if options.certificate_pem.is_empty() or options.private_key_pem.is_empty():
		return error(invalid_address())

	native := self.listen_native(address)?
	return self.listening(native, options.clone(), timeout)

// Listens on a Unix domain socket at `path`.
// Any restricted network returns EACCES, and an empty path returns EINVAL.
fn Network.listen_unix(path: String) Listener!:
	if not msstd_scope_open(self.scope): return error(closed_error())
	if not unix_allowed(self.policy): return error(denied())
	if path.is_empty(): return error(invalid_address())

	return self.listening(msstd_net_listen_unix(path)?, none, none)

// The literal addresses a socket may bind for `address`: listening must be allowed, an
// empty host means every interface (IPv6 where the host has it, else IPv4), and a name
// stands for the allowed addresses it resolves to.
fn Network.bind_targets(address: String) List[String]!:
	found := split_host_port(address)
	if not found.is_some(): return error(invalid_address())

	target := found.get()
	if not listen_allowed(self.policy, target.host): return error(denied())
	if target.host.is_empty():
		return ok(
			[
				literal_address("::", target.port),
				literal_address("0.0.0.0", target.port),
			]
		)

	var targets: List[String] = []
	for ip in self.addresses_of(target.host, none)?:
		if address_allowed(self.policy, ip): targets.append(
			literal_address(ip, target.port)
		)
	if targets.is_empty(): return error(denied())

	return ok(targets)

/*
Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
More than `options.max_records` addresses returns EOVERFLOW, `options.timeout` bounds the lookup, and a failed lookup returns EIO.
System-resolver lookups run on the runtime's blocking threads (`MS_POOL_THREADS`, default 4), at most half of them at once, while other tasks keep running.
*/
fn Network.lookup(name: String, options: DnsOptions = DnsOptions()) List[String]!:
	return dns_lookup(
		self.policy,
		self.resolver.clone(),
		name,
		options.max_records,
		options.timeout,
	)

// Performs one buffered HTTP request and returns the status, headers, and complete
// body. Only `http` and `https` URLs without user info are accepted. Redirects are
// returned, not followed, and no cookies or proxy settings apply. A body over
// `options.max_bytes` returns EOVERFLOW; error statuses are ordinary responses.
fn Network.request(
	method: HttpMethod,
	url: String,
	body: Writable = "",
	options: RequestOptions = RequestOptions(),
) ClientResponse!:
	if not msstd_scope_open(self.scope): return error(closed_error())

	client := open_client(
		self.policy,
		HttpClientOptions(max_redirects: 0),
		self.resolver.clone(),
	)?
	if not msstd_scope_track_client(self.scope, client.native): return error(
		closed_error()
	)

	outcome := buffered(
		client,
		method,
		url,
		options.headers.clone(),
		body.as_bytes(),
		options.max_bytes,
		options.timeout,
	)
	_forgotten := msstd_scope_untrack_client(self.scope, client.native)
	_closed := client.close()
	return outcome

// Looks up DNS records of one `kind` for `name`; each record carries that kind.
// `options.max_records` and `options.timeout` apply as for `lookup`.
fn Network.resolve_dns(
	name: String,
	kind: DnsKind,
	options: DnsOptions = DnsOptions(),
) List[DnsRecord]!:
	return dns_resolve(
		self.policy,
		self.resolver.clone(),
		name,
		kind,
		options.max_records,
		options.timeout,
	)

// Returns a derived network limited to the given host names and CIDR ranges. Names
// match case-insensitively without a trailing dot, and IP-literal hosts also match
// through `cidrs`. With `cidrs`, every resolved address must be inside one of them.
// `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A
// derived restriction can only narrow its parent, and closing the parent closes the
// child. Invalid host or CIDR text returns EINVAL.
fn Network.restrict(
	hosts: List[String],
	cidrs: List[String] = [],
	allow_listen: Bool = false,
) Network!:
	policy := narrow(self.policy, hosts, cidrs, allow_listen)?
	if not msstd_scope_open(self.scope): return error(closed_error())

	return ok(
		Network(
			policy: policy,
			resolver: self.resolver.clone(),
			scope: msstd_scope_child(self.scope),
		)
	)

// Opens a WebSocket client connection to a `ws` or `wss` URL with the headers and
// subprotocols in `options`. Handshake headers such as `Upgrade`, `Connection`,
// `Host`, and `Sec-WebSocket-*` cannot be set. A server that selects a subprotocol
// that was not offered fails the handshake. Failures are `Error` values.
fn Network.web_socket(
	url: String,
	options: WebSocketOptions = WebSocketOptions(),
) WebSocket!:
	if given := options.max_message_bytes:
		if given <= 0: return error(invalid_address())
	if limit := options.timeout:
		if limit.compare(nanoseconds(0)) < 0: return error(invalid_address())

	// The URL parser knows http and https; the handshake itself is HTTP/1.1.
	scheme := url.split_once(":")
	if not scheme.is_some(): return error(invalid_address())

	lead := scheme.get().before.lower()
	secure := lead == "wss"
	if lead != "ws" and not secure: return error(invalid_address())

	parsed := parse(f"{if secure: "https" else: "http"}:{scheme.get().after}")?
	if not host_allowed(self.policy, parsed.host): return error(denied())

	var tls_options = options.tls.clone()
	tls_options.alpn = ["http/1.1"]
	if tls_options.server_name.is_empty(): tls_options.server_name = parsed.host.clone()

	port := parsed.port.get_or(if secure: 443 else: 80)
	authority := if parsed.host.contains(":"): f"[{parsed.host}]" else: parsed.host.clone()
	var target = if parsed.path.is_empty(): "/" else: parsed.path.clone()
	if query := parsed.query: target += f"?{query}"

	var tls_arg: TlsOptions? = none
	if secure: tls_arg = tls_options.clone()

	started := monotonic()
	native := self.dial(f"{authority}:{port}", tls_arg, options.timeout.clone())?
	var shown = authority.clone()
	if parsed.port.is_some(): shown += f":{port}"

	left := remaining(started, options.timeout.clone())

	if left.is_error():
		msstd_conn_close(native)
		return error(left.err())

	socket := msstd_ws_connect(
		native,
		shown,
		target,
		options.headers,
		options.subprotocols,
		options.compression,
		options.max_message_bytes,
		left.get(),
	)

	if socket.is_error():
		msstd_conn_close(native)
		if not msstd_scope_open(self.scope): return error(closed_error())

		return error(socket.err())

	return ok(web_socket_from(socket.get()))

// Returns a derived network that resolves names through the DNS server at
// `address`, an IP literal with port, instead of the system resolver. The address
// must be allowed by this network's restrictions, otherwise EACCES is returned. An
// address that is not an IP literal with a port returns EINVAL.
fn Network.with_resolver(address: String) Network!:
	found := split_host_port(address)
	if not found.is_some(): return error(invalid_address())

	target := found.get()
	if parse_ip(target.host).is_error(): return error(invalid_address())
	if not host_allowed(self.policy, target.host): return error(denied())
	if not address_allowed(self.policy, target.host): return error(denied())
	if not msstd_scope_open(self.scope): return error(closed_error())

	return ok(
		Network(
			policy: self.policy.clone(),
			resolver: address,
			scope: msstd_scope_child(self.scope),
		)
	)

/*
Per-call settings of a buffered `request`: the headers to send, a bound on the response body, and a time budget.
*/
export type RequestOptions:
	// The header fields to send with the request; empty by default. Transport headers
	// such as `Host` and `Content-Length` are set by the request itself.
	headers: HttpHeaders = headers()
	// Largest accepted response body in bytes. A longer body returns EOVERFLOW; none
	// sets no limit.
	max_bytes: Int? = none
	// Time budget for the whole request; ETIMEDOUT when it elapses. none waits
	// indefinitely.
	timeout: Duration? = none

// Per-call settings of a DNS query: how many records to accept and a time budget.
export type DnsOptions:
	// More records than this returns EOVERFLOW; none sets no limit.
	max_records: Int? = none
	// Time budget for the query; ETIMEDOUT when it elapses. none waits indefinitely.
	timeout: Duration? = none

fn remaining(started: Instant, timeout: Duration?) Duration?!:
	if limit := timeout:
		left := limit.subtract(monotonic().difference(started))
		if left.compare(nanoseconds(0)) <= 0:
			return error(Error("network: timed out", kind: "ETIMEDOUT"))

		return ok(left)

	return ok(none)

// The network of the current host.
fn host_network() Network:
	return Network(policy: unrestricted(), resolver: "", scope: msstd_scope_new())

// Binds a UDP socket to `address` (`host:port`; port 0 picks a free port). A restricted
// network without listening permission, or an address outside its CIDRs, returns
// EACCES.
// ms: effect std.net.listen
export fn bind_datagram(address: String) DatagramSocket!:
	return host_network().bind_datagram(address)

// Starts resolving `address` (`host:port`) and opening a TCP connection to the first
// reachable permitted address, and returns its promise. With `tls`, it then completes a
// TLS handshake.
// `wait` gives EACCES for names or addresses a restricted network disallows, ETIMEDOUT when
// `timeout` elapses, and EIO when every address refuses or the handshake or verification
// fails.
// `tls` verifies the server certificate against `tls.roots_pem` (the system roots when
// empty) for `tls.server_name`, with at least TLS 1.2; an empty `server_name` or
// invalid options give EINVAL. `timeout` bounds the whole attempt.
// ms: effect std.net.connect
export fn connect(
	address: String,
	tls: TlsOptions? = none,
	timeout: Duration? = none,
) Promise[Connection]:
	owned_address := address.clone()
	owned_tls := tls.clone()
	owned_timeout := timeout.clone()
	return promise(
		fn: host_network().connect(owned_address, owned_tls, owned_timeout),
		options: PromiseOptions(placement: Placement.Here)
	)

// Starts connecting to the Unix domain socket at `path` and returns its promise. Any
// restricted network gives EACCES because Unix sockets bypass host and CIDR checks, and
// an empty path gives EINVAL. `timeout` bounds the attempt.
// ms: effect std.net.connect
export fn connect_unix(path: String, timeout: Duration? = none) Promise[Connection]:
	owned_path := path.clone()
	return promise(
		fn: host_network().connect_unix(owned_path, timeout),
		options: PromiseOptions(placement: Placement.Here)
	)

// Creates a reusable HTTP client with connection pooling that dials through this
// network, so its restrictions and resolver apply to every request and redirect.
// Invalid or negative options return EINVAL. Closing the network closes the client.
// ms: effect std.net.connect
export fn http_client(options: HttpClientOptions = HttpClientOptions()) HttpClient!:
	return host_network().http_client(options)

// Listens for TCP connections on `address` (`host:port`; port 0 picks a free port). A
// restricted network needs `allow_listen` and an IP-literal address inside its CIDRs,
// otherwise EACCES is returned. An address that is not an IP literal with a port
// returns EINVAL.
// ms: effect std.net.listen
export fn listen(address: String) Listener!:
	return host_network().listen(address)

// Listens for TCP connections on `address` and completes a TLS handshake for each
// accepted connection, within `timeout` when supplied.
// `options` must hold a certificate and key, otherwise EINVAL is returned.
// ms: effect std.net.listen
export fn listen_tls(
	address: String,
	options: TlsOptions,
	timeout: Duration? = none,
) Listener!:
	return host_network().listen_tls(address, options, timeout)

// Listens on a Unix domain socket at `path`.
// Any restricted network returns EACCES, and an empty path returns EINVAL.
// ms: effect std.net.listen
export fn listen_unix(path: String) Listener!:
	return host_network().listen_unix(path)

/*
Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
More than `options.max_records` addresses returns EOVERFLOW, `options.timeout` bounds the lookup, and a failed lookup returns EIO.
System-resolver lookups run on the runtime's blocking threads (`MS_POOL_THREADS`, default 4), at most half of them at once, while other tasks keep running.
*/
// ms: effect std.net.connect
export fn lookup(name: String, options: DnsOptions = DnsOptions()) List[String]!:
	return host_network().lookup(name, options)

// Performs one buffered HTTP request and returns the status, headers, and complete
// body. Only `http` and `https` URLs without user info are accepted. Redirects are
// returned, not followed, and no cookies or proxy settings apply. A body over
// `options.max_bytes` returns EOVERFLOW; error statuses are ordinary responses.
// ms: effect std.net.connect
export fn request(
	method: HttpMethod,
	url: String,
	body: Writable = "",
	options: RequestOptions = RequestOptions(),
) ClientResponse!:
	return host_network().request(method, url, body, options)

// Looks up DNS records of one `kind` for `name`; each record carries that kind.
// `options.max_records` and `options.timeout` apply as for `lookup`.
// ms: effect std.net.connect
export fn resolve_dns(
	name: String,
	kind: DnsKind,
	options: DnsOptions = DnsOptions(),
) List[DnsRecord]!:
	return host_network().resolve_dns(name, kind, options)

// Returns a derived network limited to the given host names and CIDR ranges. Names
// match case-insensitively without a trailing dot, and IP-literal hosts also match
// through `cidrs`. With `cidrs`, every resolved address must be inside one of them.
// `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A
// derived restriction can only narrow its parent, and closing the parent closes the
// child. Invalid host or CIDR text returns EINVAL.
export fn restrict(
	hosts: List[String],
	cidrs: List[String] = [],
	allow_listen: Bool = false,
) Network!:
	return host_network().restrict(hosts, cidrs, allow_listen)

// Starts an HTTP server on `address` whose handler receives each request as an
// exchange: read the body and write the response incrementally, or use `read_body`,
// `reply`, and `buffered` from `@std/net/http.ms` for whole messages. Limits, timeouts,
// and TLS come from `options`. A request beyond `max_requests` concurrent requests is
// answered with 503, an oversized header block with 431, and a handler fault with 500.
// An address that cannot be bound returns EIO, and invalid options (`cores` below 1
// included) return EINVAL. Close the server, or drop it, to stop it.
//
// `serve` binds a plain TCP listener and runs the accept loop as a promise. It starts one
// worker per core (`options.cores`), each placed on the least loaded thread, and deals
// each accepted connection to the next worker, which keeps it. HTTP/1.1, HTTP/2 and the
// TLS handshake of `options.tls` run in the worker. `handler` is built once and only
// read by every thread. `options.cores` limits the runtime to that many threads (none:
// every core).
//
// A handler is cancelled when its request times out or its client disconnects (an
// HTTP/1 connection closes or an HTTP/2 stream is reset): its waits end and its
// resource cleanup runs. A client that half-closes its end after sending the request
// counts as disconnected. A faulting handler's frames release the heap values they own,
// as a cancelled handler's do. Return an error response for expected failures instead
// of faulting.
// ms: effect std.net.listen
export fn serve(
	address: String,
	handler: fn(var HttpExchange) Void!,
	options: HttpServerOptions = HttpServerOptions()
) HttpServer!:
	return start_server(address, handler, options)

// Opens a WebSocket client connection to a `ws` or `wss` URL with the headers and
// subprotocols in `options`. Handshake headers such as `Upgrade`, `Connection`, `Host`,
// and `Sec-WebSocket-*` cannot be set. A server that selects a subprotocol that was not
// offered fails the handshake. Failures are `Error` values.
// ms: effect std.net.connect
export fn web_socket(
	url: String,
	options: WebSocketOptions = WebSocketOptions(),
) WebSocket!:
	return host_network().web_socket(url, options)

// Returns a derived network that resolves names through the DNS server at `address`, an
// IP literal with port, instead of the system resolver. The address must be allowed by
// this network's restrictions, otherwise EACCES is returned. An address that is not an
// IP literal with a port returns EINVAL.
// ms: effect std.net.connect
export fn with_resolver(address: String) Network!:
	return host_network().with_resolver(address)
