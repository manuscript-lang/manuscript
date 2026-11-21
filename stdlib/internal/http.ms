import (
	Bytes from "@std/bytes.ms",
	NativeExchange from "@std/net/exchange.ms",
	HttpClientWire,
	HttpExchange,
	HttpHeaders,
	HttpResponseMetadata,
	HttpServerOptions,
	NativeAdmission,
	NativeConnection,
	NativeH2Conn,
	NativeHandler,
	NativeHttpClient,
	NativeResponseBody,
	NativeTlsServer,
	RawResponse from "@std/net/http.ms",
	Duration from "@std/time.ms",
)

// The HTTP client natives (runtime/net/fetch.c).
export extern fn msstd_client_new(options: HttpClientWire) NativeHttpClient!

// Another handle on the same client, for a promise that sends a request on it.
export extern fn msstd_client_share(handle: NativeHttpClient) NativeHttpClient

// Ends the client's transfers and refuses later requests.
export extern fn msstd_client_close(handle: NativeHttpClient) Void

// Adds one level to the client's host and address filter; before the first request.
export extern fn msstd_client_narrow(
	handle: NativeHttpClient,
	hosts: List[String],
	cidrs: List[String],
) Void!

export extern fn msstd_client_fetch(
	handle: NativeHttpClient,
	method: String,
	url: String,
	headers: HttpHeaders,
	body: Bytes,
	timeout: Duration?,
) NativeResponseBody!

export extern fn msstd_body_close(handle: NativeResponseBody) Void

export extern fn msstd_body_metadata(handle: NativeResponseBody) HttpResponseMetadata

export extern fn msstd_body_read(handle: NativeResponseBody, max_bytes: Int?) Bytes?!

export extern fn msstd_body_read_all(handle: NativeResponseBody, max_bytes: Int?) Bytes!

export extern fn msstd_headers_append(
	headers: HttpHeaders,
	name: String,
	value: Bytes,
) Void!

export extern fn msstd_headers_values(value: HttpHeaders, name: String) List[Bytes]?

export extern fn msstd_headers_names(value: HttpHeaders) List[String]

export extern fn msstd_headers_remove(value: HttpHeaders, name: String) Bool

export extern fn msstd_headers_clone(value: HttpHeaders) HttpHeaders

export extern fn msstd_headers_new() HttpHeaders

// Limits the scheduler threads the runtime starts to `n` (at least 1).
export extern fn msrt_runtime_set_threads(n: Int) Void

export extern fn msrt_runtime_limit() Int

// The server side of one HTTP/1 exchange (runtime/include/ms_rt/xchg.h). `timeout` is a
// per-call budget; none waits until the task is cancelled.

export extern fn msstd_xchg_method(x: NativeExchange) String

export extern fn msstd_xchg_target(x: NativeExchange) String

export extern fn msstd_xchg_protocol(x: NativeExchange) String

export extern fn msstd_xchg_headers(x: NativeExchange) HttpHeaders

export extern fn msstd_xchg_share(x: NativeExchange) NativeExchange

export extern fn msstd_xchg_read(
	x: NativeExchange,
	max_bytes: Int?,
	timeout: Duration?,
) Bytes?!

export extern fn msstd_xchg_send_head(
	x: NativeExchange,
	status: Int,
	headers: HttpHeaders,
	length: Int?,
	timeout: Duration?,
) Void!

export extern fn msstd_xchg_write(
	x: NativeExchange,
	data: Bytes,
	timeout: Duration?,
) Void!

// Ends the response; true when the connection can carry another request.
export extern fn msstd_xchg_finish(x: NativeExchange, timeout: Duration?) Bool!

export extern fn msstd_xchg_reset(
	x: NativeExchange,
	max_bytes: Int,
	timeout: Duration?,
) Void!

// Takes the connection out of the exchange once a 101 head is sent, for a WebSocket:
// the bytes the runtime read ahead go with it. An exchange gives its connection up
// once.
export extern fn msstd_xchg_take_conn(x: NativeExchange) NativeConnection!

// The accept side of one connection (runtime/include/ms_rt/xchg.h). `next` reads the
// next request head of an HTTP/1 connection: none when the peer closed before sending a
// byte, and an error otherwise (a refused head leaves the status to answer in
// `reject_status`).
export extern fn msstd_xchg_next(
	connection: NativeConnection,
	head_limit: Int,
	timeout: Duration?,
) NativeExchange?!

export extern fn msstd_xchg_reject_status(connection: NativeConnection) Int

export extern fn msstd_xchg_reject(
	connection: NativeConnection,
	status: Int,
	timeout: Duration?,
) Void!

// Returns once the peer is gone from the exchange: it closed or half-closed an HTTP/1
// connection, or reset the HTTP/2 stream. An error is this task's cancellation.
export extern fn msstd_xchg_wait_gone(x: NativeExchange) Void!

// HTTP/2 on an accepted connection. `open` starts it (0 limits mean defaults); one task
// runs `run` for the life of the connection and another takes requests with `next`,
// none once the connection is over. `drain` sends GOAWAY and lets requests in flight
// finish.
export extern fn msstd_h2_open(
	connection: NativeConnection,
	max_streams: Int,
	max_header_list: Int,
	stream_window: Int,
	connection_window: Int,
	idle: Duration?,
) NativeH2Conn!

export extern fn msstd_h2_run(h2: NativeH2Conn) Void!

export extern fn msstd_h2_next(h2: NativeH2Conn, timeout: Duration?) NativeExchange?!

export extern fn msstd_h2_drain(h2: NativeH2Conn) Void

export extern fn msstd_h2_share(h2: NativeH2Conn) NativeH2Conn

// The count of requests running at once, shared by every thread of one server.
export extern fn msstd_admit_new(max: Int?) NativeAdmission

export extern fn msstd_admit_share(admission: NativeAdmission) NativeAdmission

// An error when the limit is reached; nothing is counted then.
export extern fn msstd_admit_enter(admission: NativeAdmission) Void!

export extern fn msstd_admit_leave(admission: NativeAdmission) Void

// The handler of a server, shared by every thread. `run` serves one request: it takes
// the exchange `call` hands it with `take` first and reports with `keep` whether the
// connection can carry another request.
export extern fn msstd_handler_new(move run: fn() Void) NativeHandler

export extern fn msstd_handler_share(handler: NativeHandler) NativeHandler

// Serves one request with the handler, in the calling task; true when the connection
// can carry another.
export extern fn msstd_handler_call(handler: NativeHandler, x: NativeExchange) Bool!

export extern fn msstd_handler_take() NativeExchange

export extern fn msstd_handler_keep(keep: Bool) Void

// Idle connections (runtime/include/ms_rt/xchg.h). After a response that keeps the
// connection alive, the serving task parks it here and ends; the pool starts `next` as a
// promise when the peer sends the next request, on a thread that is not held up.
export extern fn msstd_idle_park(
	connection: NativeConnection,
	move next: fn() Void,
	group: Int,
	timeout: Duration?,
) Void!

export extern fn msstd_idle_group() Int

export extern fn msstd_idle_drain(group: Int) Void

export extern fn msstd_idle_inflight(group: Int) Int

export extern fn msstd_idle_cancel(group: Int) Void
