import (
	Bytes from "@std/bytes.ms",
	Promise, complete, deferred, owned_task, promise from "@std/concurrency/promise.ms",
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
	headers from "@std/net/http.ms",
	Cidr, DnsKind, DnsRecord, IpAddress from "@std/net/ip.ms",
	TlsInfo, TlsOptions from "@std/net/tls.ms",
	WebSocket,
	WebSocketOptions,
	WebSocketWire,
	web_socket_from from "@std/net/websocket.ms",
	Duration, Timestamp, sleep from "@std/time.ms",

	msrt_runtime_limit,
	msrt_runtime_set_threads,
	msstd_http_serving_accept,
	msstd_http_serving_address,
	msstd_http_serving_new,
	msstd_http_serving_release,
	msstd_http_serving_share,
	msstd_http_serving_worker,
	msstd_http_worker_adopt,
	msstd_http_worker_close from "@std/internal/http.ms",
	msstd_net_connection_close,
	msstd_net_connection_close_if_last,
	msstd_net_connection_local_address,
	msstd_net_connection_peer_address,
	msstd_net_connection_read,
	msstd_net_connection_share,
	msstd_net_connection_shutdown_write,
	msstd_net_connection_tls_info,
	msstd_net_connection_write_bytes,
	msstd_net_datagram_address,
	msstd_net_datagram_close,
	msstd_net_datagram_close_if_last,
	msstd_net_datagram_receive,
	msstd_net_datagram_send_bytes,
	msstd_net_datagram_share,
	msstd_net_listener_accept,
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
	msstd_net_network_with_resolver from "@std/internal/net.ms",
)

// The runtime handle behind a `Connection`.
export extern type NativeConnection

type ConnectionSource:
	native: NativeConnection

impl Source[Bytes] for ConnectionSource:
	// Waits for the next chunk; none at the end of the stream.
	var fn next() Bytes?!:
		return msstd_net_connection_read(self.native, none, none)

	// Closes the socket when the output end is already closed.
	var fn close() Unit!:
		msstd_net_connection_close_if_last(self.native)

type ConnectionSink:
	native: NativeConnection

impl Sink[Bytes] for ConnectionSink:
	var fn write(value: Bytes) Unit!:
		return msstd_net_connection_write_bytes(self.native, value, none)

	var fn flush() Unit!:
		return ok(unit)

	// Half-closes the connection so the peer sees the end of the stream; the socket closes once the input is closed too.
	var fn close() Unit!:
		_ := msstd_net_connection_shutdown_write(self.native)
		msstd_net_connection_close_if_last(self.native)

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
	// A connection that is not TLS returns EINVAL.
	fn tls_info() TlsInfo!:
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

impl Closeable for Connection:
	// Closes both streams, and with them the socket.
	var fn close() Unit!:
		self.input.close()?
		return self.output.close()

// Wraps a native socket into a `Connection`.
fn connection(native: NativeConnection) Connection:
	local := msstd_net_connection_local_address(native)
	peer := msstd_net_connection_peer_address(native)
	var tls: TlsInfo? = none

	match msstd_net_connection_tls_info(native):
		ok(found): tls = found
		error(_): tls = none

	other := msstd_net_connection_share(native)
	return Connection(
		input: ReadStream[Bytes](ConnectionSource(native)),
		output: WriteStream[Bytes](ConnectionSink(other)),
		info: ConnectionInfo(local, peer, tls)
	)

// One datagram. Received, `address` is where it came from; written, where it goes.
export type Datagram:
	// The payload bytes of this datagram, at most 65535 bytes.
	data: Bytes
	// Native host:port text, with bracketed IPv6 addresses.
	address: String

// The runtime handle behind a `DatagramSocket`.
export extern type NativeDatagramSocket

type DatagramSource:
	native: NativeDatagramSocket

impl Source[Datagram] for DatagramSource:
	// Waits for one datagram, at most 65535 bytes; a larger one is an error of kind `EOVERFLOW` and is discarded.
	var fn next() Datagram?!:
		return ok(msstd_net_datagram_receive(self.native, none, none)?)

	var fn close() Unit!:
		msstd_net_datagram_close_if_last(self.native)

type DatagramSink:
	native: NativeDatagramSocket

impl Sink[Datagram] for DatagramSink:
	// Sends `value.data` as one datagram to `value.address`, resolving a host name with the network's resolver.
	var fn write(value: Datagram) Unit!:
		return msstd_net_datagram_send_bytes(
			self.native, value.data, value.address, none
		)

	var fn flush() Unit!:
		return ok(unit)

	var fn close() Unit!:
		msstd_net_datagram_close_if_last(self.native)

// A connectionless socket for sending and receiving datagrams. Closing it closes both streams.
export type DatagramSocket:
	// Datagrams received, with the sender's address.
	input: ReadStream[Datagram]
	// Datagrams to send; each carries its destination.
	output: WriteStream[Datagram]
	// The bound local address as `host:port` text, which reveals the port chosen when binding port 0.
	address: String

impl Closeable for DatagramSocket:
	// Closes both streams, and with them the socket.
	var fn close() Unit!:
		self.input.close()?
		return self.output.close()

fn datagram_socket(native: NativeDatagramSocket) DatagramSocket:
	address := msstd_net_datagram_address(native)
	other := msstd_net_datagram_share(native)
	return DatagramSocket(
		input: ReadStream[Datagram](DatagramSource(native)),
		output: WriteStream[Datagram](DatagramSink(other)), address: address
	)

// The runtime handle behind a `Listener`.
export extern type NativeListener

// A listening socket that accepts incoming connections.
// Several tasks may call `accept` on one listener (an accept pool); each incoming connection goes to exactly one of them.
export opaque type Listener:
	// The runtime handle; it is released by `close` and owned by this value.
	native: NativeListener

impl Closeable for Listener:
	// Stops accepting, interrupts a pending `accept`, and waits for it to stop.
	// Safe to call repeatedly; connections already accepted stay open.
	var fn close() Unit!:
		msstd_net_listener_close(self.native)

impl Listener:
	// Starts waiting for the next incoming connection and returns its promise. A timeout gives ETIMEDOUT and a closed listener gives EBADF from `wait`.
	// On a TLS listener the handshake completes before the connection is returned; a failed handshake drops that connection and gives EIO.
	fn accept(timeout: Duration? = none) Promise[Connection]:
		return owned_task[Connection](
			accept_job(msstd_net_listener_share(self.native), timeout)
		)

	// Returns the bound local address as `host:port` text, which reveals the port chosen when listening on port 0.
	fn address() String:
		return msstd_net_listener_address(self.native)

// The work of `accept`: a returned closure owns its own handle on the listener and the time it waits.
fn accept_job(native: NativeListener, timeout: Duration?) fn() Connection!:
	return fn: ok(connection(msstd_net_listener_accept(native, timeout)?))

// The runtime handle behind a `Network`.
export extern type NativeNetwork

// A set of network permissions and a resolver for the connections, listeners, sockets, clients and servers opened through it. Nothing restricts the host network.
export opaque type Network:
	// The runtime handle; it is released when the last reference to this network ends.
	native: NativeNetwork

impl Network:
	// Binds a UDP socket to `address` (`host:port`; port 0 picks a free port).
	// A restricted network without listening permission, or an address outside its CIDRs, returns EACCES.
	fn bind_datagram(address: String) DatagramSocket!:
		return ok(
			datagram_socket(
				msstd_net_network_bind_datagram(self.native, address)?
			)
		)

	// Cancels in-flight calls and closes every connection, listener, socket, HTTP client, and server this network opened, including those of derived networks.
	// Safe to call repeatedly. A request handler of a server on this network cannot close it and faults.
	fn close() Unit:
		msstd_net_network_close(self.native)

	// Resolves `address` (`host:port`) and opens a TCP connection to the first reachable permitted address, completing a TLS handshake with `tls` when given.
	// The wait happens in the calling task; the module-level `connect` starts the same work as a promise.
	// Returns EACCES for names or addresses a restricted network disallows, ETIMEDOUT when `timeout` elapses, and EIO when every address refuses or the handshake or verification fails.
	// `tls` verifies the server certificate against `tls.roots_pem` (the system roots when empty) for `tls.server_name`, with at least TLS 1.2; an empty `server_name` or invalid options return EINVAL. `timeout` bounds the whole attempt.
	fn connect(
		address: String,
		tls: TlsOptions? = none,
		timeout: Duration? = none
	) Connection!:
		if options := tls:
			if options.server_name.is_empty():
				return error(Error("network: invalid input", kind: "EINVAL"))
			return ok(
				connection(
					msstd_net_network_connect_tls_config(
						self.native, address, options, timeout
					)?
				)
			)

		return ok(connection(msstd_net_network_connect(self.native, address, timeout)?))

	// Connects to the Unix domain socket at `path`.
	// Any restricted network returns EACCES because Unix sockets bypass host and CIDR checks, and an empty path returns EINVAL. `timeout` bounds the attempt.
	fn connect_unix(path: String, timeout: Duration? = none) Connection!:
		return ok(
			connection(
				msstd_net_network_connect_unix(
					self.native, path, timeout
				)?
			)
		)

	// Creates a reusable HTTP client with connection pooling that dials through this network, so its restrictions and resolver apply to every request and redirect.
	// Invalid or negative options return EINVAL. Closing the network closes the client.
	fn http_client(options: HttpClientOptions = HttpClientOptions()) HttpClient!:
		return msstd_net_network_http_client(self.native, options)

	// Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
	// A restricted network needs `allow_listen` and an IP-literal address inside its CIDRs, otherwise EACCES is returned. An address that is not an IP literal with a port returns EINVAL.
	fn listen(address: String) Listener!:
		return msstd_net_network_listen(self.native, address)

	// Listens for TCP connections on `address` and completes a TLS handshake for each accepted connection, within `timeout` when supplied.
	// `options` must hold a certificate and key, otherwise EINVAL is returned.
	fn listen_tls(
		address: String,
		options: TlsOptions,
		timeout: Duration? = none
	) Listener!:
		return msstd_net_network_listen_tls(self.native, address, options, timeout)

	// Listens on a Unix domain socket at `path`.
	// Any restricted network returns EACCES, and an empty path returns EINVAL.
	fn listen_unix(path: String) Listener!:
		return msstd_net_network_listen_unix(self.native, path)

	/*
    Resolves a host name to its IPv4 and IPv6 address strings through the network's resolver.
    More than `options.max_records` addresses returns EOVERFLOW, `options.timeout` bounds the lookup, and a failed lookup returns EIO.
    System-resolver lookups run on the runtime's blocking threads (`MS_POOL_THREADS`, default 4), at most half of them at once, while other tasks keep running.
    */
	fn lookup(name: String, options: DnsOptions = DnsOptions()) List[String]!:
		return msstd_net_network_lookup(
			self.native, name, options.max_records, options.timeout
		)

	// Performs one buffered HTTP request and returns the status, headers, and complete body.
	// Only `http` and `https` URLs without user info are accepted. Redirects are returned, not followed, and no cookies or proxy settings apply. A body over `options.max_bytes` returns EOVERFLOW; error statuses are ordinary responses.
	fn request(
		method: HttpMethod,
		url: String,
		body: Writable = "",
		options: RequestOptions = RequestOptions()
	) ClientResponse!:
		return msstd_net_network_request_bytes(
			self.native, method.text(), url, options.headers, body.as_bytes(),
			options.max_bytes, options.timeout
		)

	// Resolves the selected supported category, retaining it in each record.
	fn resolve(
		name: String,
		kind: DnsKind,
		options: DnsOptions = DnsOptions()
	) List[DnsRecord]!:
		return msstd_net_network_resolve(
			self.native, name, kind, options.max_records, options.timeout
		)

	// Returns a derived network limited to the given host names and CIDR ranges.
	// Names match case-insensitively without a trailing dot, and IP-literal hosts also match through `cidrs`. With `cidrs`, every resolved address must be inside one of them. `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A derived restriction can only narrow its parent, and closing the parent closes the child. Invalid host or CIDR text returns EINVAL.
	fn restrict(
		hosts: List[String],
		cidrs: List[String] = [],
		allow_listen: Bool = false
	) Network!:
		return msstd_net_network_restrict(self.native, hosts, cidrs, allow_listen)

	// Opens a WebSocket client connection to a `ws` or `wss` URL with the headers and subprotocols in `options`.
	// Handshake headers such as `Upgrade`, `Connection`, `Host`, and `Sec-WebSocket-*` cannot be set. A server that selects a subprotocol that was not offered fails the handshake. Failures are `Error` values.
	fn web_socket(
		url: String,
		options: WebSocketOptions = WebSocketOptions()
	) WebSocket!:
		subprotocols := options.subprotocols.clone()
		wire := WebSocketWire(
			max_message_bytes: options.max_message_bytes, timeout: options.timeout,
			tls: options.tls.clone(), compression: options.compression
		)
		return ok(
			web_socket_from(
				msstd_net_network_web_socket(
					self.native, url, options.headers, subprotocols, wire
				)?
			)
		)

	// Returns a derived network that resolves names through the DNS server at `address`, an IP literal with port, instead of the system resolver.
	// The address must be allowed by this network's restrictions, otherwise EACCES is returned. An address that is not an IP literal with a port returns EINVAL.
	fn with_resolver(address: String) Network!:
		return msstd_net_network_with_resolver(self.native, address)

/*
Per-call settings of a buffered `request`: the headers to send, a bound on the response body, and a time budget.
*/
export type RequestOptions:
	// The header fields to send with the request; empty by default. Transport headers such as `Host` and `Content-Length` are set by the request itself.
	headers: HttpHeaders = headers()
	// Largest accepted response body in bytes. A longer body returns EOVERFLOW; none sets no limit.
	max_bytes: Int? = none
	// Time budget for the whole request; ETIMEDOUT when it elapses. none waits indefinitely.
	timeout: Duration? = none

// Per-call settings of a DNS query: how many records to accept and a time budget.
export type DnsOptions:
	// More records than this returns EOVERFLOW; none sets no limit.
	max_records: Int? = none
	// Time budget for the query; ETIMEDOUT when it elapses. none waits indefinitely.
	timeout: Duration? = none

// The network of the current host.
fn host_network() Network:
	return Network(native: msstd_net_network())

// Binds a UDP socket to `address` (`host:port`; port 0 picks a free port).
// A restricted network without listening permission, or an address outside its CIDRs, returns EACCES.
// ms: effect std.net.listen
export fn bind_datagram(address: String) DatagramSocket!:
	return host_network().bind_datagram(address)

// Starts resolving `address` (`host:port`) and opening a TCP connection to the first reachable permitted address, and returns its promise. With `tls`, it then completes a TLS handshake.
// `wait` gives EACCES for names or addresses a restricted network disallows, ETIMEDOUT when `timeout` elapses, and EIO when every address refuses or the handshake or verification fails.
// `tls` verifies the server certificate against `tls.roots_pem` (the system roots when empty) for `tls.server_name`, with at least TLS 1.2; an empty `server_name` or invalid options give EINVAL. `timeout` bounds the whole attempt.
// ms: effect std.net.connect
export fn connect(
	address: String,
	tls: TlsOptions? = none,
	timeout: Duration? = none
) Promise[Connection]:
	return owned_task[Connection](connect_job(address.clone(), tls.clone(), timeout))

// Starts connecting to the Unix domain socket at `path` and returns its promise.
// Any restricted network gives EACCES because Unix sockets bypass host and CIDR checks, and an empty path gives EINVAL. `timeout` bounds the attempt.
// ms: effect std.net.connect
export fn connect_unix(path: String, timeout: Duration? = none) Promise[Connection]:
	return owned_task[Connection](connect_unix_job(path.clone(), timeout))

// The work of `connect` and `connect_unix`: a returned closure owns its address (or socket path), TLS settings and time.
fn connect_job(address: String, tls: TlsOptions?, timeout: Duration?) fn() Connection!:
	return fn: host_network().connect(address, tls, timeout)

fn connect_unix_job(path: String, timeout: Duration?) fn() Connection!:
	return fn: host_network().connect_unix(path, timeout)

// Creates a reusable HTTP client with connection pooling that dials through this network, so its restrictions and resolver apply to every request and redirect.
// Invalid or negative options return EINVAL. Closing the network closes the client.
// ms: effect std.net.connect
export fn http_client(options: HttpClientOptions = HttpClientOptions()) HttpClient!:
	return host_network().http_client(options)

// Listens for TCP connections on `address` (`host:port`; port 0 picks a free port).
// A restricted network needs `allow_listen` and an IP-literal address inside its CIDRs, otherwise EACCES is returned. An address that is not an IP literal with a port returns EINVAL.
// ms: effect std.net.listen
export fn listen(address: String) Listener!:
	return host_network().listen(address)

// Listens for TCP connections on `address` and completes a TLS handshake for each accepted connection, within `timeout` when supplied.
// `options` must hold a certificate and key, otherwise EINVAL is returned.
// ms: effect std.net.listen
export fn listen_tls(
	address: String,
	options: TlsOptions,
	timeout: Duration? = none
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

// Performs one buffered HTTP request and returns the status, headers, and complete body.
// Only `http` and `https` URLs without user info are accepted. Redirects are returned, not followed, and no cookies or proxy settings apply. A body over `options.max_bytes` returns EOVERFLOW; error statuses are ordinary responses.
// ms: effect std.net.connect
export fn request(
	method: HttpMethod,
	url: String,
	body: Writable = "",
	options: RequestOptions = RequestOptions()
) ClientResponse!:
	return host_network().request(method, url, body, options)

// Resolves the selected supported category, retaining it in each record.
// ms: effect std.net.connect
export fn resolve_dns(
	name: String,
	kind: DnsKind,
	options: DnsOptions = DnsOptions()
) List[DnsRecord]!:
	return host_network().resolve(name, kind, options)

// Returns a derived network limited to the given host names and CIDR ranges.
// Names match case-insensitively without a trailing dot, and IP-literal hosts also match through `cidrs`. With `cidrs`, every resolved address must be inside one of them. `allow_listen` permits listening within the CIDRs. Unix sockets are refused. A derived restriction can only narrow its parent, and closing the parent closes the child. Invalid host or CIDR text returns EINVAL.
export fn restrict(
	hosts: List[String],
	cidrs: List[String] = [],
	allow_listen: Bool = false
) Network!:
	return host_network().restrict(hosts, cidrs, allow_listen)

// Starts an HTTP server on `address` whose handler receives each request as an exchange: read the body and write the response incrementally, or use `read_body`, `reply`, and `buffered` from `@std/net/http.ms` for whole messages. Limits, timeouts, and TLS come from `options`.
// A request beyond `max_requests` concurrent requests is answered with 503, an oversized header block with 431, and a handler fault with 500. An address that cannot be bound returns EIO.
// Returns EINVAL for invalid options (`cores` below 1 included). Close the server, or drop it, to stop it.
// `serve` binds a plain TCP listener and runs the accept loop as a promise. Each accepted connection becomes a promise of its own, which the runtime places on the least busy thread, where it stays; HTTP/1.1, HTTP/2 and the TLS handshake of `options.tls` run there. `handler` is built once and only read by every thread. `options.cores` limits the runtime to that many threads (none: every core).
// A handler is cancelled when its request times out or its client disconnects (an HTTP/1 connection closes or an HTTP/2 stream is reset): its waits end and its resource cleanup runs. A client that half-closes its end after sending the request counts as disconnected.
// A faulting handler's frames release the heap values they own, as a cancelled handler's do. Return an error response for expected failures instead of faulting.
// ms: effect std.net.listen
export fn serve(
	address: String,
	handler: fn(var HttpExchange) Unit!,
	options: HttpServerOptions = HttpServerOptions()
) HttpServer!:
	if cores := options.cores:
		if cores < 1: return error(Error("network: invalid input", kind: "EINVAL"))

	serving := msstd_http_serving_new(address, options, handler)?
	bound := msstd_http_serving_address(serving)
	listening := ServingHandle(serving: serving, listener: true)
	if cores := options.cores:
		msrt_runtime_set_threads(cores)

	// The accept loop owns the listener; each worker owns a share of the serving and a pipe of accepted connections.
	workers := workers_for(options)
	accepting := promise(fn: accept_loop(listening, workers))
	return ok(HttpServer(accepting: accepting, bound: bound, stopped: false))

// The number of worker promises: `options.cores`, else one per core.
fn workers_for(options: HttpServerOptions) Int:
	return options.cores.get(msrt_runtime_limit())

// A handle on a serving, which a promise owns and closes when it ends. The accept loop's handle also releases the listener.
type ServingHandle:
	serving: NativeServing
	listener: Bool

impl Closeable for ServingHandle:
	var fn close() Unit!:
		if self.listener:
			msstd_http_serving_release(self.serving)

// One worker's HTTP engine, which owns its connections as poller registrations rather than as tasks. Closing it drains them.
type WorkerHandle:
	worker: NativeWorker

impl Closeable for WorkerHandle:
	var fn close() Unit!:
		msstd_http_worker_close(self.worker)

// The accept loop's pipes and workers. Its close, which runs when the loop returns, is cancelled or faults, ends the pipes so the workers drain side by side, then joins them.
type Accepting:
	deals: List[WriteStream[Int]]
	workers: List[Promise[Unit]]

impl Closeable for Accepting:
	var fn close() Unit!:
		while not self.deals.is_empty():
			if deal := self.deals.pop():
				var closing = deal
				_ := closing.close()

		for worker in self.workers:
			worker.cancel()
		self.workers = []

// Accepts until the listener fails, dealing each connection to the next worker. An accept that fails for lack of descriptors or memory pauses briefly instead of ending the server.
fn accept_loop(listening: ServingHandle, count: Int) Unit!:
	var accepting = Accepting(deals: [], workers: [])
	var i = 0

	while i < count:
		queue := pipe[Int](1024)
		accepting.deals.append(queue.writer())

		mine := ServingHandle(
			serving: msstd_http_serving_share(listening.serving), listener: false
		)
		accepting.workers.append(promise(fn: serve_worker(mine, queue)))
		i += 1

	var next = 0

	while true:
		accepted := msstd_http_serving_accept(listening.serving)

		if accepted.is_error():
			if accepted.err().kind == "EBADF": return ok(unit)

			sleep(50.milliseconds()).wait().get(unit)
			continue

		_ := accepting.deals[next].write(accepted.get())
		next = (next + 1) % count

// Runs one worker on the thread the runtime placed this promise on: it adopts each connection it is dealt, and the poller drives them from there.
fn serve_worker(handle: ServingHandle, input: Pipe[Int]) Unit!:
	engine := WorkerHandle(worker: msstd_http_serving_worker(handle.serving)?)

	while true:
		item := input.receive()
		if item.is_error(): break

		if raw := item.get():
			msstd_http_worker_adopt(engine.worker, raw)
		else:
			break

// Opens a WebSocket client connection to a `ws` or `wss` URL with the headers and subprotocols in `options`.
// Handshake headers such as `Upgrade`, `Connection`, `Host`, and `Sec-WebSocket-*` cannot be set. A server that selects a subprotocol that was not offered fails the handshake. Failures are `Error` values.
// ms: effect std.net.connect
export fn web_socket(
	url: String,
	options: WebSocketOptions = WebSocketOptions()
) WebSocket!:
	return host_network().web_socket(url, options)

// Returns a derived network that resolves names through the DNS server at `address`, an IP literal with port, instead of the system resolver.
// The address must be allowed by this network's restrictions, otherwise EACCES is returned. An address that is not an IP literal with a port returns EINVAL.
// ms: effect std.net.connect
export fn with_resolver(address: String) Network!:
	return host_network().with_resolver(address)
