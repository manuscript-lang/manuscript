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
	ClientResponse,
	HttpClient,
	HttpClientOptions,
	HttpExchange,
	HttpHeaders,
	HttpMethod,
	HttpServer,
	HttpServerOptions,
	NativeServing,
	NativeWorker,
	NativeWorkerSpec,
	headers,
	native_handler from "@std/net/http.ms",
	Cidr, DnsKind, DnsRecord, IpAddress from "@std/net/ip.ms",
	TlsInfo, TlsOptions from "@std/net/tls.ms",
	WebSocket,
	WebSocketOptions,
	WebSocketWire,
	web_socket_from from "@std/net/websocket.ms",
	Duration, Timestamp, nanoseconds, sleep from "@std/time.ms",

	msrt_runtime_limit,
	msrt_runtime_set_threads,
	msstd_http_serving_accept,
	msstd_http_serving_address,
	msstd_http_serving_new,
	msstd_http_serving_release,
	msstd_http_serving_spec,
	msstd_http_serving_worker,
	msstd_http_worker_adopt,
	msstd_http_worker_close from "@std/internal/http.ms",
	msstd_net_connection_accept_tls,
	msstd_net_connection_adopt,
	msstd_net_connection_alias,
	msstd_net_connection_close,
	msstd_net_connection_close_if_last,
	msstd_net_connection_local_address,
	msstd_net_connection_peer_address,
	msstd_net_connection_read,
	msstd_net_connection_share,
	msstd_net_connection_shutdown_write,
	msstd_net_connection_start_tls,
	msstd_net_connection_tls_info,
	msstd_net_connection_write_bytes,
	msstd_net_datagram_address,
	msstd_net_datagram_close,
	msstd_net_datagram_close_if_last,
	msstd_net_datagram_receive,
	msstd_net_datagram_send_bytes,
	msstd_net_datagram_share,
	msstd_net_listener_accept,
	msstd_net_listener_accept_raw,
	msstd_net_listener_address,
	msstd_net_listener_close,
	msstd_net_listener_share,
	msstd_net_network,
	msstd_net_network_bind_datagram,
	msstd_net_network_close,
	msstd_net_network_connect,
	msstd_net_network_connect_tls_config,
	msstd_net_network_connect_unix,
	msstd_net_network_http_client,
	msstd_net_network_listen,
	msstd_net_network_listen_tls,
	msstd_net_network_listen_unix,
	msstd_net_network_lookup,
	msstd_net_network_request_bytes,
	msstd_net_network_resolve,
	msstd_net_network_restrict,
	msstd_net_network_web_socket,
	msstd_net_network_with_resolver,
	msstd_net_pending_release from "@std/internal/net.ms",
)

// The runtime handle behind a `Connection`.
export extern type NativeConnection

type ConnectionSource:
	native: NativeConnection

// Waits for the next chunk; null at the end of the stream.
fn var ConnectionSource.next() move Bytes?!:
	return msstd_net_connection_read(self.native, null, null)

// Closes the socket when the output end is already closed.
fn move ConnectionSource.close() Void!:
	msstd_net_connection_close_if_last(self.native)

type ConnectionSink:
	native: NativeConnection

fn var ConnectionSink.write(move value: Bytes) Void!:
	return msstd_net_connection_write_bytes(self.native, value, null)

fn var ConnectionSink.flush() Void!:
	return ok()

// Half-closes the connection so the peer sees the end of the stream; the socket
// closes once the input is closed too.
fn move ConnectionSink.close() Void!:
	void msstd_net_connection_shutdown_write(self.native)
	msstd_net_connection_close_if_last(self.native)

// What is known about a connection, available after its streams are moved elsewhere.
export type ConnectionInfo:
	// This end's address as `host:port` text, with IPv6 hosts in brackets; for Unix
	// sockets it is the socket path.
	local_address: String
	// The remote end's address as `host:port` text, with IPv6 hosts in brackets.
	peer_address: String
	// The negotiated TLS version, cipher suite, protocol, and peer certificates; null
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
	// Bytes from the peer; a read ends with null at the peer's end of stream.
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
fn connection(move native: NativeConnection) Connection:
	local := msstd_net_connection_local_address(native)
	peer := msstd_net_connection_peer_address(native)
	var tls: TlsInfo? = null

	match msstd_net_connection_tls_info(native):
		ok(found): tls = found
		error(_): tls = null

	other := msstd_net_connection_share(native)
	upgradable := msstd_net_connection_alias(native)
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
	timeout: Duration? = null,
) Connection!:
	if options.server_name.is_empty():
		return error(Error("network: invalid input", kind: "EINVAL"))

	upgraded := msstd_net_connection_start_tls(plain.native, options, timeout)?
	return ok(connection(upgraded))

// Upgrades a plain TCP connection to TLS in place on the server side: it accepts the
// client's handshake with the certificate and key in `options`, then returns the TLS
// connection, consuming `plain` as `start_tls` does. `options` must hold a certificate
// and key, otherwise EINVAL is returned; the other errors match `start_tls`.
export fn accept_tls(
	var plain: Connection,
	options: TlsOptions = TlsOptions(),
	timeout: Duration? = null,
) Connection!:
	upgraded := msstd_net_connection_accept_tls(plain.native, options, timeout)?
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
fn var DatagramSource.next() move Datagram?!:
	return ok(msstd_net_datagram_receive(self.native, null, null)?)

fn move DatagramSource.close() Void!:
	msstd_net_datagram_close_if_last(self.native)

type DatagramSink:
	native: NativeDatagramSocket

// Sends `value.data` as one datagram to `value.address`, resolving a host name with
// the network's resolver.
fn var DatagramSink.write(move value: Datagram) Void!:
	return msstd_net_datagram_send_bytes(self.native, value.data, value.address, null)

fn var DatagramSink.flush() Void!:
	return ok()

fn move DatagramSink.close() Void!:
	msstd_net_datagram_close_if_last(self.native)

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

fn datagram_socket(move native: NativeDatagramSocket) DatagramSocket:
	address := msstd_net_datagram_address(native)
	other := msstd_net_datagram_share(native)
	return DatagramSocket(
		input: ReadStream[Datagram](DatagramSource(native)),
		output: WriteStream[Datagram](DatagramSink(other)),
		address: address,
	)

// The runtime handle behind a `Listener`.
export extern type NativeListener

// A listening socket that accepts incoming connections. Several tasks may call `accept`
// on one listener (an accept pool); each incoming connection goes to exactly one of
// them.
export opaque type Listener:
	// The runtime handle; it is released by `close` and owned by this value.
	native: NativeListener

// Stops accepting, interrupts a pending `accept`, and waits for it to stop.
// Safe to call repeatedly; connections already accepted stay open.
fn move Listener.close() Void!:
	msstd_net_listener_close(self.native)

// Starts waiting for the next incoming connection and returns its promise. A
// timeout gives ETIMEDOUT and a closed listener gives EBADF from `wait`. On a TLS
// listener the handshake completes before the connection is returned; a failed
// handshake drops that connection and gives EIO.
fn Listener.accept(timeout: Duration? = null) Promise[Connection]:
	native := msstd_net_listener_share(self.native)
	return promise(
		fn: accepted(native, timeout),
		options: PromiseOptions(placement: Placement.Here)
	)

// Starts waiting for the next incoming connection without binding it to a thread, and
// returns its promise. A timeout gives ETIMEDOUT and a closed listener gives EBADF from
// `wait`, as for `accept`. A TLS listener gives EINVAL: its handshake belongs to the
// accepting thread.
fn Listener.accept_pending(timeout: Duration? = null) Promise[PendingConnection]:
	native := msstd_net_listener_share(self.native)
	return promise(
		fn: accepted_pending(native, timeout),
		options: PromiseOptions(placement: Placement.Here)
	)

// Returns the bound local address as `host:port` text, which reveals the port
// chosen when listening on port 0.
fn Listener.address() String:
	return msstd_net_listener_address(self.native)

// The work of `accept`, on its own handle on the listener.
fn accepted(native: NativeListener, timeout: Duration?) Connection!:
	return ok(connection(msstd_net_listener_accept(native, timeout)?))

fn accepted_pending(native: NativeListener, timeout: Duration?) PendingConnection!:
	return ok(PendingConnection(raw: msstd_net_listener_accept_raw(native, timeout)?))

// An accepted connection that no thread has taken yet. A connection belongs to the
// thread that uses it, so accepting and using it are two steps: the listener's thread
// accepts, and whichever thread should serve the connection calls `adopt`. Move it into
// a promise placed with `Placement.Spread` to serve connections on every core, as
// `serve` does for HTTP. Closing it without adopting closes the socket.
export opaque type PendingConnection:
	// The socket handle, or -1 once adopted or closed.
	raw: Int

// Closes the socket unless it was adopted. Safe to call repeatedly.
fn move PendingConnection.close() Void!:
	if self.raw >= 0:
		msstd_net_pending_release(self.raw)
		self.raw = -1

// Turns the pending connection into a `Connection` owned by the calling thread.
// Adopting twice returns EBADF.
fn var PendingConnection.adopt() Connection!:
	if self.raw < 0: return error(Error("network: closed", kind: "EBADF"))

	raw := self.raw
	self.raw = -1
	return ok(connection(msstd_net_connection_adopt(raw)?))

// The runtime handle behind a `Network`.
export extern type NativeNetwork

// A set of network permissions and a resolver for the connections, listeners, sockets,
// and HTTP clients opened through it. The host network that the module-level functions
// use is unrestricted; `restrict` derives a narrower one.
export opaque type Network:
	// The runtime handle; it is released when the last reference to this network ends.
	native: NativeNetwork

// Binds a UDP socket to `address` (`host:port`; port 0 picks a free port). A
// restricted network without listening permission, or an address outside its CIDRs,
// returns EACCES.
fn Network.bind_datagram(address: String) DatagramSocket!:
	return ok(datagram_socket(msstd_net_network_bind_datagram(self.native, address)?))

// Cancels in-flight calls and closes every connection, listener, socket, HTTP
// client, and server this network opened, including those of derived networks. Safe
// to call repeatedly. A request handler of a server on this network cannot close it
// and faults.
fn Network.close() Void:
	msstd_net_network_close(self.native)

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
	tls: TlsOptions? = null,
	timeout: Duration? = null,
) Connection!:
	if options := tls:
		if options.server_name.is_empty():
			return error(Error("network: invalid input", kind: "EINVAL"))
		return ok(
			connection(
				msstd_net_network_connect_tls_config(
					self.native,
					address,
					options,
					timeout,
				)?
			)
		)

	return ok(connection(msstd_net_network_connect(self.native, address, timeout)?))

// Connects to the Unix domain socket at `path`. Any restricted network returns
// EACCES because Unix sockets bypass host and CIDR checks, and an empty path
// returns EINVAL. `timeout` bounds the attempt.
fn Network.connect_unix(path: String, timeout: Duration? = null) Connection!:
	return ok(connection(msstd_net_network_connect_unix(self.native, path, timeout)?))

// Creates a reusable HTTP client with connection pooling that dials through this
// network, so its restrictions and resolver apply to every request and redirect.
// Invalid or negative options return EINVAL. Closing the network closes the client.
fn Network.http_client(options: HttpClientOptions = HttpClientOptions()) HttpClient!:
	return msstd_net_network_http_client(self.native, options)

// Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
// A restricted network needs `allow_listen` and an IP-literal address inside its
// CIDRs, otherwise EACCES is returned. An address that is not an IP literal with a
// port returns EINVAL.
fn Network.listen(address: String) Listener!:
	return msstd_net_network_listen(self.native, address)

// Listens for TCP connections on `address` and completes a TLS handshake for each
// accepted connection, within `timeout` when supplied.
// `options` must hold a certificate and key, otherwise EINVAL is returned.
fn Network.listen_tls(
	address: String,
	options: TlsOptions,
	timeout: Duration? = null,
) Listener!:
	return msstd_net_network_listen_tls(self.native, address, options, timeout)

// Listens on a Unix domain socket at `path`.
// Any restricted network returns EACCES, and an empty path returns EINVAL.
fn Network.listen_unix(path: String) Listener!:
	return msstd_net_network_listen_unix(self.native, path)

/*
Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
More than `options.max_records` addresses returns EOVERFLOW, `options.timeout` bounds the lookup, and a failed lookup returns EIO.
System-resolver lookups run on the runtime's blocking threads (`UV_THREADPOOL_SIZE`, default 4), at most half of them at once, while other tasks keep running.
*/
fn Network.lookup(name: String, options: DnsOptions = DnsOptions()) List[String]!:
	return msstd_net_network_lookup(
		self.native,
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
	return msstd_net_network_request_bytes(
		self.native,
		method.to_string(),
		url,
		options.headers,
		body.as_bytes(),
		options.max_bytes,
		options.timeout,
	)

// Looks up DNS records of one `kind` for `name`; each record carries that kind.
// `options.max_records` and `options.timeout` apply as for `lookup`.
fn Network.resolve_dns(
	name: String,
	kind: DnsKind,
	options: DnsOptions = DnsOptions(),
) List[DnsRecord]!:
	return msstd_net_network_resolve(
		self.native,
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
	return msstd_net_network_restrict(self.native, hosts, cidrs, allow_listen)

// Opens a WebSocket client connection to a `ws` or `wss` URL with the headers and
// subprotocols in `options`. Handshake headers such as `Upgrade`, `Connection`,
// `Host`, and `Sec-WebSocket-*` cannot be set. A server that selects a subprotocol
// that was not offered fails the handshake. Failures are `Error` values.
fn Network.web_socket(
	url: String,
	options: WebSocketOptions = WebSocketOptions(),
) WebSocket!:
	subprotocols := options.subprotocols.clone()
	wire := WebSocketWire(
		max_message_bytes: options.max_message_bytes,
		timeout: options.timeout,
		tls: options.tls.clone(),
		compression: options.compression,
	)
	return ok(
		web_socket_from(
			msstd_net_network_web_socket(
				self.native,
				url,
				options.headers,
				subprotocols,
				wire,
			)?
		)
	)

// Returns a derived network that resolves names through the DNS server at
// `address`, an IP literal with port, instead of the system resolver. The address
// must be allowed by this network's restrictions, otherwise EACCES is returned. An
// address that is not an IP literal with a port returns EINVAL.
fn Network.with_resolver(address: String) Network!:
	return msstd_net_network_with_resolver(self.native, address)

/*
Per-call settings of a buffered `request`: the headers to send, a bound on the response body, and a time budget.
*/
export type RequestOptions:
	// The header fields to send with the request; empty by default. Transport headers
	// such as `Host` and `Content-Length` are set by the request itself.
	headers: HttpHeaders = headers()
	// Largest accepted response body in bytes. A longer body returns EOVERFLOW; null
	// sets no limit.
	max_bytes: Int? = null
	// Time budget for the whole request; ETIMEDOUT when it elapses. null waits
	// indefinitely.
	timeout: Duration? = null

// Per-call settings of a DNS query: how many records to accept and a time budget.
export type DnsOptions:
	// More records than this returns EOVERFLOW; null sets no limit.
	max_records: Int? = null
	// Time budget for the query; ETIMEDOUT when it elapses. null waits indefinitely.
	timeout: Duration? = null

// The network of the current host.
fn host_network() Network:
	return Network(native: msstd_net_network())

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
	tls: TlsOptions? = null,
	timeout: Duration? = null,
) Promise[Connection]:
	owned_address := address.clone()
	owned_tls := tls.clone()
	return promise(
		fn: host_network().connect(owned_address, owned_tls, timeout),
		options: PromiseOptions(placement: Placement.Here)
	)

// Starts connecting to the Unix domain socket at `path` and returns its promise. Any
// restricted network gives EACCES because Unix sockets bypass host and CIDR checks, and
// an empty path gives EINVAL. `timeout` bounds the attempt.
// ms: effect std.net.connect
export fn connect_unix(path: String, timeout: Duration? = null) Promise[Connection]:
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
	timeout: Duration? = null,
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
System-resolver lookups run on the runtime's blocking threads (`UV_THREADPOOL_SIZE`, default 4), at most half of them at once, while other tasks keep running.
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
// read by every thread. `options.cores` limits the runtime to that many threads (null:
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
	move handler: fn(var HttpExchange) Void!,
	options: HttpServerOptions = HttpServerOptions()
) HttpServer!:
	if cores := options.cores:
		if cores < 1: return error(Error("network: invalid input", kind: "EINVAL"))

	serving := msstd_http_serving_new(address, options, native_handler(handler))?
	bound := msstd_http_serving_address(serving)
	listening := ServingHandle(serving: serving)
	if cores := options.cores:
		msrt_runtime_set_threads(cores)

	// The accept loop owns the listener; each worker owns a share of the options and
	// handler and a pipe of accepted connections.
	workers := workers_for(options)
	accepting := promise(fn: accept_loop(listening, workers))
	return ok(HttpServer(accepting: accepting, bound: bound, stopped: false))

// The number of worker promises: `options.cores`, else one per core.
fn workers_for(options: HttpServerOptions) Int:
	return options.cores or msrt_runtime_limit()

// The serving, which the accept loop owns and releases (and so closes the listener)
// when it ends. Workers get a share of what they use, so the listener never leaves its
// thread.
type ServingHandle:
	serving: NativeServing

fn move ServingHandle.close() Void!:
	msstd_http_serving_release(self.serving)

// One worker's HTTP engine, which owns its connections as poller registrations rather
// than as tasks. Closing it drains them.
type WorkerHandle:
	worker: NativeWorker

fn move WorkerHandle.close() Void!:
	msstd_http_worker_close(self.worker)

// The accept loop's pipes and workers. Its close, which runs when the loop returns, is
// cancelled or faults, ends the pipes so the workers drain side by side, then joins
// them.
type Accepting:
	deals: List[WriteStream[Int]]
	workers: List[Promise[Void]]

fn move Accepting.close() Void!:
	while not self.deals.is_empty():
		if deal := self.deals.pop():
			var closing = deal
			void closing.close()

	for worker in self.workers:
		worker.cancel()
	self.workers = []

// Accepts until the listener fails, dealing each connection to the next worker. An
// accept that fails for lack of descriptors or memory pauses briefly instead of ending
// the server.
fn accept_loop(listening: ServingHandle, count: Int) Void!:
	var accepting = Accepting(deals: [], workers: [])
	var i = 0

	while i < count:
		queue := pipe[Int](1024)
		accepting.deals.append(queue.writer())

		spec := msstd_http_serving_spec(listening.serving)
		accepting.workers.append(start_worker(spec, queue))
		i += 1

	var next = 0

	// The back-off, in nanoseconds, between accept attempts that failed for a reason no
	// retry fixes (EMFILE, ENFILE, ENOBUFS, ENOMEM): 5 ms, doubling up to 1 s.
	var pause = 5000000

	while true:
		accepted := msstd_http_serving_accept(listening.serving)

		if accepted.is_error():
			if accepted.err().kind == "EBADF": return ok()

			// The runtime already retried the errors of a single connection. What is
			// left (out of descriptors or memory) waits for something to close, longer
			// each time.
			void sleep(nanoseconds(pause)).wait()
			pause = if pause < 500000000: pause * 2 else: 1000000000
			continue

		pause = 5000000
		void accepting.deals[next].write(accepted.get())
		next = (next + 1) % count

// Starts one worker on the least loaded thread. A returned promise owns what it
// captures, so the share of the serving and the pipe belong to the worker for as long
// as it runs.
fn start_worker(move spec: NativeWorkerSpec, move input: Pipe[Int]) Promise[Void]:
	return promise(
		fn: serve_worker(spec, input),
		options: PromiseOptions(placement: Placement.Spread)
	)

// Runs one worker on the thread the runtime placed this promise on: it adopts each
// connection it is dealt, and the poller drives them from there.
fn serve_worker(spec: NativeWorkerSpec, input: Pipe[Int]) Void!:
	engine := WorkerHandle(worker: msstd_http_serving_worker(spec)?)

	while true:
		item := input.receive()
		if item.is_error(): break

		if raw := item.get():
			msstd_http_worker_adopt(engine.worker, raw)
		else:
			break

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
