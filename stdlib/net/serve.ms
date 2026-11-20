import (
	Cancel,
	Placement,
	Promise,
	PromiseOptions,
	Signal,
	cancel_switch,
	promise,
	set_options,
	wait_any from "@std/concurrency/promise.ms",
	stderr from "@std/io/io.ms",
	ExchangeLimits,
	NativeExchange,
	finish_exchange,
	open_exchange from "@std/net/exchange.ms",
	HttpExchange,
	HttpServer,
	HttpServerOptions,
	NativeAdmission,
	NativeConnection,
	NativeH2Conn,
	NativeHandler,
	NativeListener,
	NativeTlsServer,
	headers from "@std/net/http.ms",
	TlsOptions from "@std/net/tls.ms",
	hold_stop from "@std/os/process.ms",
	Duration, nanoseconds, sleep from "@std/time.ms",

	msrt_runtime_limit,
	msrt_runtime_set_threads,
	msstd_admit_enter,
	msstd_admit_leave,
	msstd_admit_new,
	msstd_admit_share,
	msstd_h2_drain,
	msstd_h2_next,
	msstd_h2_open,
	msstd_h2_run,
	msstd_h2_share,
	msstd_handler_call,
	msstd_handler_keep,
	msstd_handler_new,
	msstd_handler_share,
	msstd_handler_take,
	msstd_xchg_finish,
	msstd_xchg_method,
	msstd_xchg_next,
	msstd_xchg_reject,
	msstd_xchg_reject_status,
	msstd_xchg_send_head,
	msstd_xchg_share,
	msstd_xchg_target,
	msstd_xchg_wait_gone from "@std/internal/http.ms",
	msstd_conn_accept_tls_with,
	msstd_conn_alpn,
	msstd_conn_close,
	msstd_conn_share,
	msstd_listener_accept,
	msstd_listener_address,
	msstd_listener_close,
	msstd_listener_share,
	msstd_net_listen,
	msstd_tls_server_new,
	msstd_tls_server_share from "@std/internal/net.ms",
)

// The HTTP server: the accept loop, one promise per connection, and one per request.
//
// A connection promise is placed on the least loaded thread and serves its connection
// from there. HTTP/1.1 connections read one request head at a time; HTTP/2 connections
// (negotiated through ALPN on a TLS listener) run the runtime's connection task next to
// a loop that starts a request promise for each stream. Either way a request is the
// same
// `NativeExchange`, so the handler cannot tell them apart.

// Request head cap when `max_header_bytes` is none.
DEFAULT_HEAD_LIMIT := 1048576

// What every request of one server follows; plain data a connection promise copies.
type Rules:
	// Per-request limits the exchange enforces for its handler.
	limits: ExchangeLimits
	// Largest request head, in bytes.
	head_limit: Int
	// The request deadline, which also bounds an idle or slow HTTP/1 connection.
	timeout: Duration?

fn invalid() Error:
	return Error("HTTP: invalid input", kind: "EINVAL")

// Whether `limit` is absent or at least `least`.
fn at_least(least: Int, limit: Int?) Bool:
	if given := limit: return given >= least
	return true

// Checks the options and returns the rules they set.
fn rules_of(options: HttpServerOptions) Rules!:
	if not at_least(1, options.max_requests): return error(invalid())
	if not at_least(0, options.max_body_bytes): return error(invalid())
	if not at_least(0, options.max_response_bytes): return error(invalid())
	if not at_least(1, options.max_header_bytes): return error(invalid())

	if span := options.timeout:
		if span.to_nanoseconds() <= 0: return error(invalid())
	if span := options.grace:
		if span.to_nanoseconds() < 0: return error(invalid())
	if cores := options.cores:
		if cores < 1: return error(invalid())

	head := options.max_header_bytes.get_or(DEFAULT_HEAD_LIMIT)
	return ok(
		Rules(
			limits: ExchangeLimits(
				max_body_bytes: options.max_body_bytes,
				max_response_bytes: options.max_response_bytes,
				max_header_bytes: head,
				secure: options.tls.clone().is_some(),
			),
			head_limit: head,
			timeout: options.timeout.clone(),
		)
	)

// The TLS settings the listener serves with: HTTP/1.1 unless the options name
// protocols.
fn tls_server(options: HttpServerOptions) NativeTlsServer?!:
	given := options.tls.clone()
	if not given.is_some(): return ok(none)

	chosen := given.get()
	var alpn = chosen.alpn.clone()
	if alpn.is_empty(): alpn = ["http/1.1"]
	return ok(
		msstd_tls_server_new(
			TlsOptions(
				server_name: chosen.server_name.clone(),
				roots_pem: chosen.roots_pem.clone(),
				certificate_pem: chosen.certificate_pem.clone(),
				private_key_pem: chosen.private_key_pem.clone(),
				alpn: alpn,
				require_client_certificate: chosen.require_client_certificate,
			)
		)?
	)

// Starts a server on `address`: the accept loop runs as a promise, which `HttpServer`
// owns. The handler goes into a runtime object that every thread's connection tasks
// call (a closure has one owner, and a connection promise on another thread cannot
// borrow it).
export fn start_server(
	address: String,
	handler: fn(var HttpExchange) Void!,
	options: HttpServerOptions = HttpServerOptions()
) HttpServer!:
	rules := rules_of(options)?
	secured := tls_server(options)?
	listener := msstd_net_listen(address)?
	bound := msstd_listener_address(listener)
	if cores := options.cores: msrt_runtime_set_threads(cores)

	admission := msstd_admit_new(options.max_requests)
	request_rules := rules.clone()
	serving := msstd_handler_new(fn: serve_one(handler, request_rules, admission))
	var state = Accepting(
		listener: listener,
		drain: cancel_switch(),
		live: [],
		grace: options.grace.clone(),
	)
	stopping := cancel_switch()
	accepting := begin_accepting(state, serving, rules, stopping.signal(), secured)
	return ok(
		HttpServer(
			accepting: accepting,
			bound: bound,
			stopped: false,
			stopping: stopping,
		)
	)

// Starts the accept loop; a promise a function returns owns what it captures.
fn begin_accepting(
	move state: Accepting,
	serving: NativeHandler,
	rules: Rules,
	stop: Signal,
	secured: NativeTlsServer?,
) Promise[Void]:
	var accepting = state
	return promise(fn: accept_loop(accepting, serving, rules, stop, secured))

// The accept loop's state: the listener, the connections it started, and the switch
// that asks them to finish. Its close, which runs when the loop returns, is cancelled
// or faults, stops accepting, lets requests in flight finish within the grace period
// and cancels what is left.
type Accepting:
	listener: NativeListener
	// Fired by close: idle connections end and busy ones finish their request.
	drain: Cancel
	live: List[Promise[Void]]
	grace: Duration?

fn move Accepting.close() Void!:
	self.finish()
	void self.drain.close()

// Stops accepting, asks the connections to finish, and waits for them.
fn var Accepting.finish() Void:
	msstd_listener_close(self.listener)
	self.drain.cancel()

	if span := self.grace:
		if span.to_nanoseconds() == 0:
			for connection in self.live:
				connection.cancel()
		else:
			for connection in self.live:
				set_options(connection, PromiseOptions(timeout: span.clone()))

	// Each wait takes one promise's end; dropping the rest cancels and joins them.
	while not self.live.is_empty():
		if connection := self.live.pop():
			void connection.wait()

// Drops the connections that have ended, so a long-lived server holds only live ones.
fn var Accepting.prune() Void:
	var kept: List[Promise[Void]] = []

	while not self.live.is_empty():
		if connection := self.live.pop():
			if connection.done():
				void connection.wait()
			else:
				kept.append(connection)

	self.live = kept

fn accept_loop(
	var accepting: Accepting,
	serving: NativeHandler,
	rules: Rules,
	stop: Signal,
	secured: NativeTlsServer?,
) Void!:
	var checked_at = 64

	// The back-off, in nanoseconds, between accept attempts that failed for a reason no
	// retry fixes (EMFILE, ENFILE, ENOBUFS, ENOMEM): 5 ms, doubling up to 1 s.
	var pause = 5000000

	while true:
		shared := msstd_listener_share(accepting.listener)
		waiting := promise(
			fn: msstd_listener_accept(shared, none),
			options: PromiseOptions(
				placement: Placement.Here,
				cancel: stop.clone(),
			)
		)
		accepted := waiting.wait()

		if accepted.is_error():
			if accepted.err().kind == "EBADF": return ok()

			if accepted.err().kind == "ECANCELED":
				accepting.finish()
				return ok()

			// The runtime already retried the errors of a single connection. What is
			// left (out of descriptors or memory) waits for something to close, longer
			// each time.
			void sleep(nanoseconds(pause)).wait()
			pause = if pause < 500000000: pause * 2 else: 1000000000
			continue

		pause = 5000000

		if accepting.live.length() >= checked_at:
			accepting.prune()
			checked_at = max_of(64, accepting.live.length() * 2)

		accepting.live.append(
			start_connection(
				accepted.get(),
				msstd_handler_share(serving),
				rules.clone(),
				accepting.drain.signal(),
				accepting.grace.clone(),
				share_tls(secured),
			)
		)

fn max_of(a: Int, b: Int) Int:
	return if a > b: a else: b

fn share_tls(server: NativeTlsServer?) NativeTlsServer?:
	if given := server: return msstd_tls_server_share(given)
	return none

// Starts the promise that serves one connection on the least loaded thread. It owns
// what it captures, so the connection and the shares belong to it for as long as it
// runs.
fn start_connection(
	raw: NativeConnection,
	serving: NativeHandler,
	rules: Rules,
	drain: Signal,
	grace: Duration?,
	secured: NativeTlsServer?,
) Promise[Void]:
	// Ending the promise (the accept loop unwinding on a stop request) fires the drain
	// first and cancels the connection only after the grace period.
	ending := drain.clone()
	return promise(
		fn: serve_connection(raw, serving, rules, drain, secured),
		options: PromiseOptions(
			placement: Placement.Spread,
			drain: ending,
			grace: grace,
		)
	)

// Serves one accepted connection to its end: the TLS handshake when the listener has
// one, then HTTP/2 or HTTP/1.1 by what the handshake chose.
fn serve_connection(
	raw: NativeConnection,
	serving: NativeHandler,
	rules: Rules,
	drain: Signal,
	secured: NativeTlsServer?,
) Void!:
	// The connection ends through the drain, not through a stop request (see `call`).
	_hold := hold_stop()

	// A connection belongs to the thread that uses it, so this one adopts it.
	var conn = msstd_conn_share(raw)

	if server := secured:
		upgraded := msstd_conn_accept_tls_with(conn, server, rules.timeout.clone())

		// A failed handshake already closed the connection.
		if upgraded.is_error(): return ok()

		conn = upgraded.get()

	if msstd_conn_alpn(conn) == "h2":
		return serve_h2(conn, serving, rules, drain)
	else:
		return serve_h1(conn, serving, rules, drain)

// ---- HTTP/1.1 ----

// The next request head, or none when the connection should end: the peer closed, the
// head was refused (and answered), it took too long, or the server is draining. The
// wait is a promise of its own so that draining ends an idle connection at once.
fn next_head(conn: NativeConnection, rules: Rules, drain: Signal) NativeExchange?:
	waiting := promise(
		fn: msstd_xchg_next(conn, rules.head_limit, rules.timeout.clone()),
		options: PromiseOptions(
			placement: Placement.Here,
			cancel: drain.clone(),
		)
	)
	got := waiting.wait()

	if got.is_error():
		refused := msstd_xchg_reject_status(conn)
		if refused > 0: void msstd_xchg_reject(conn, refused, rules.timeout.clone())
		return none

	return got.get()

fn serve_h1(
	conn: NativeConnection,
	serving: NativeHandler,
	rules: Rules,
	drain: Signal,
) Void!:
	while not drain.cancelled():
		head := next_head(conn, rules, drain.clone())
		if not head.is_some(): break

		kept := msstd_handler_call(serving, head.get())
		if kept.is_error() or not kept.get(): break

	msstd_conn_close(conn)
	return ok()

// ---- HTTP/2 ----

fn serve_h2(
	conn: NativeConnection,
	serving: NativeHandler,
	rules: Rules,
	drain: Signal,
) Void!:
	opened := msstd_h2_open(conn, 0, rules.head_limit, 0, 0, rules.timeout.clone())

	if opened.is_error():
		msstd_conn_close(conn)
		return ok()

	h2 := opened.get()

	// The connection task: it reads the socket and wakes the requests.
	running := promise(
		fn: msstd_h2_run(msstd_h2_share(h2)),
		options: PromiseOptions(placement: Placement.Here)
	)
	var requests: List[Promise[Void]] = []
	var draining = false

	while true:
		// Draining sends GOAWAY once; requests already started finish.
		if drain.cancelled() and not draining:
			draining = true
			msstd_h2_drain(h2)

		var stop: Signal? = drain.clone()
		if draining: stop = none

		waiting := promise(
			fn: msstd_h2_next(msstd_h2_share(h2), none),
			options: PromiseOptions(placement: Placement.Here, cancel: stop)
		)
		got := waiting.wait()

		if got.is_error():
			if drain.cancelled() and not draining: continue

			break

		if request := got.get():
			requests.append(start_stream(request, msstd_handler_share(serving)))
		else:
			break

	while not requests.is_empty():
		if request := requests.pop():
			void request.wait()
	void running.wait()
	return ok()

fn start_stream(request: NativeExchange, serving: NativeHandler) Promise[Void]:
	return promise(
		fn: serve_stream(request, serving),
		options: PromiseOptions(placement: Placement.Here)
	)

fn serve_stream(request: NativeExchange, serving: NativeHandler) Void!:
	void msstd_handler_call(serving, request)
	return ok()

// ---- one request ----

// Serves the request `msstd_handler_call` handed this task, as the closure of the
// serving: the handler runs next to a watcher, and the response ends. It leaves in
// `keep` whether the connection can carry another request.
fn serve_one(
	handler: fn(var HttpExchange) Void!,
	rules: Rules,
	admission: NativeAdmission
) Void:
	native := msstd_handler_take()
	msstd_handler_keep(serve_request(native, handler, rules, admission))

// Answers `status` with no body, ending the exchange.
fn answer(native: NativeExchange, status: Int) Void:
	fields := headers()
	void msstd_xchg_send_head(native, status, fields, 0, none)
	void msstd_xchg_finish(native, none)

// Runs the handler on the exchange of `native`; 400 when the target cannot be routed.
fn call(
	handler: fn(var HttpExchange) Void!,
	native: NativeExchange,
	limits: ExchangeLimits
) Int!:
	// A stop request (SIGINT, SIGTERM) must not end a request in flight: the drain and
	// its grace period decide that, so the request holds the stop back until it is
	// done.
	_hold := hold_stop()
	opened := open_exchange(native, limits)
	if opened.is_error(): return ok(400)

	var exchange = opened.get()
	handler(exchange)?
	return ok(0)

// The fault report up to the first frame of this server: the handler's own frames.
fn handler_frames(report: String) String:
	var kept = ""

	for line in report.split("\n"):
		if (
			line.index_of("@std/").is_some()
			or line.index_of("task started by").is_some()
		): break

		if not line.is_empty(): kept = kept + line + "\n"

	return kept

// Cancels the handler once the peer is gone from the exchange.
fn watch(native: NativeExchange, stopper: Cancel) Void!:
	if msstd_xchg_wait_gone(native).is_ok(): stopper.cancel()
	return ok()

// Runs the handler of one request and ends its response; true when the connection can
// carry another request. The handler is cancelled when its time passes (the request is
// answered 504) and when the peer goes away.
fn serve_request(
	native: NativeExchange,
	handler: fn(var HttpExchange) Void!,
	rules: Rules,
	admission: NativeAdmission
) Bool:
	if msstd_admit_enter(admission).is_error():
		answer(native, 503)
		return false

	kept := run_handler(native, handler, rules)
	msstd_admit_leave(admission)
	return kept

fn run_handler(
	native: NativeExchange,
	handler: fn(var HttpExchange) Void!,
	rules: Rules
) Bool:
	// The asterisk form names the server itself, which only OPTIONS may ask about.
	if msstd_xchg_target(native) == "*" and msstd_xchg_method(native) != "OPTIONS":
		answer(native, 400)
		return false

	stopper := cancel_switch()
	limits := rules.limits.clone()
	running := promise(
		fn: call(handler, native, limits.clone()),
		options: PromiseOptions(
			placement: Placement.Here,
			timeout: rules.timeout.clone(),
			cancel: stopper.signal(),
		)
	)
	gone := promise(
		fn: watch(msstd_xchg_share(native), stopper),
		options: PromiseOptions(placement: Placement.Here)
	)
	outcome := running.wait()
	gone.cancel()

	if outcome.is_error():
		kind := outcome.err().kind

		// A handler that faulted answers 500; its report goes to the diagnostics.
		if report := outcome.err().details.get("report"):
			void stderr().write(f"HTTP stream handler fault: {handler_frames(report)}")

		if kind == "ETIMEDOUT":
			answer(native, 504)
			return false

		// The peer left or the server stopped waiting: nobody reads a response.
		if kind == "ECANCELED": return false

		return finish_exchange(native, outcome.err())

	if outcome.get() != 0:
		answer(native, outcome.get())
		return false

	return finish_exchange(native, none)
