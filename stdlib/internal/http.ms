import (
	Bytes from "@std/bytes.ms",
	NativeExchange from "@std/net/exchange.ms",
	HttpClientWire,
	HttpExchange,
	HttpHeaders,
	HttpResponseMetadata,
	HttpServerOptions,
	NativeHttpClient,
	NativeResponseBody,
	NativeServing,
	NativeWorker,
	NativeWorkerSpec,
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

export extern fn msstd_http_serving_new(
	address: String,
	options: HttpServerOptions,
	move handler: fn(var HttpExchange) Void!
) NativeServing!

// Another handle on the same serving, for a connection promise to own.
// What one worker needs from the serving, as plain data a worker promise owns.
export extern fn msstd_http_serving_spec(serving: NativeServing) NativeWorkerSpec

export extern fn msstd_http_serving_address(serving: NativeServing) String

export extern fn msstd_http_serving_accept(serving: NativeServing) Int!

// A worker engine on the calling thread; it adopts connections and serves them from the
// poller.
export extern fn msstd_http_serving_worker(spec: NativeWorkerSpec) NativeWorker!

export extern fn msstd_http_worker_adopt(worker: NativeWorker, connection: Int) Void

// Drains the worker's connections and ends it.
export extern fn msstd_http_worker_close(worker: NativeWorker) Void

export extern fn msstd_http_serving_release(serving: NativeServing) Void

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
