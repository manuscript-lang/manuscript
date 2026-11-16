import (
	Bytes from "@std/bytes.ms",
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

export extern fn msstd_http_client_close(handle: NativeHttpClient) Void

export extern fn msstd_http_client_share(handle: NativeHttpClient) NativeHttpClient

export extern fn msstd_http_client_request_bytes(
	handle: NativeHttpClient,
	method: String,
	url: String,
	headers: HttpHeaders,
	body: Bytes,
	max_response_bytes: Int?,
	timeout: Duration?,
) RawResponse!

export extern fn msstd_http_serving_new(
	address: String,
	options: HttpServerOptions,
	handler: fn(var HttpExchange) Void!
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

export extern fn msstd_http_body_close(handle: NativeResponseBody) Void

export extern fn msstd_http_body_metadata(
	handle: NativeResponseBody
) HttpResponseMetadata

export extern fn msstd_http_body_read(
	handle: NativeResponseBody,
	max_bytes: Int?,
) Bytes?!

export extern fn msstd_http_body_read_all(handle: NativeResponseBody) Bytes!

export extern fn msstd_http_headers_append(
	headers: HttpHeaders,
	name: String,
	value: Bytes,
) Void!

export extern fn msstd_http_headers_values(
	value: HttpHeaders,
	name: String,
) List[Bytes]?

export extern fn msstd_http_headers_names(value: HttpHeaders) List[String]

export extern fn msstd_http_headers_remove(value: HttpHeaders, name: String) Bool

export extern fn msstd_http_headers_clone(value: HttpHeaders) HttpHeaders

export extern fn msstd_http_headers_new() HttpHeaders

// Limits the scheduler threads the runtime starts to `n` (at least 1).
export extern fn msrt_runtime_set_threads(n: Int) Void

export extern fn msrt_runtime_limit() Int
