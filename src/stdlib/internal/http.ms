import (
	Bytes from "@std/bytes.ms",
	HttpExchange,
	HttpHeaders,
	HttpResponseMetadata,
	HttpServerOptions,
	NativeAccepted,
	NativeExchange,
	NativeHttpClient,
	NativeResponseBody,
	NativeServing,
	NativeWorker,
	NativeWorkerSpec,
	RawResponse from "@std/net/http.ms",
	NativeWebSocket from "@std/net/websocket.ms",
	Duration from "@std/time.ms",
)

export extern fn msstd_http_client_close(handle: NativeHttpClient) Void

export extern fn msstd_http_client_share(handle: NativeHttpClient) move NativeHttpClient

export extern fn msstd_http_client_request_bytes(
	handle: NativeHttpClient,
	method: String,
	url: String,
	headers: HttpHeaders,
	body: Bytes,
	max_response_bytes: Int?,
	timeout: Duration?,
) move RawResponse!

export extern fn msstd_http_serving_new(
	address: String,
	options: HttpServerOptions,
	move handler: fn(move NativeExchange) Int
) move NativeServing!

// Another handle on the same serving, for a connection promise to own.
// What one worker needs from the serving, as plain data a worker promise owns.
export extern fn msstd_http_serving_spec(serving: NativeServing) move NativeWorkerSpec

export extern fn msstd_http_serving_address(serving: NativeServing) move String

// The next connection, owned by the returned handle until a worker adopts it.
export extern fn msstd_http_serving_accept(serving: NativeServing) move NativeAccepted!

// A worker engine on the calling thread; it adopts connections and serves them from the
// poller.
export extern fn msstd_http_serving_worker(spec: NativeWorkerSpec) move NativeWorker!

// Takes the connection out of `accepted`; a closed worker leaves it there to close with
// the handle.
export extern fn msstd_http_worker_adopt(
	worker: NativeWorker,
	accepted: NativeAccepted,
) Void

// Drains the worker's connections and ends it.
export extern fn msstd_http_worker_close(worker: NativeWorker) Void

export extern fn msstd_http_serving_release(serving: NativeServing) Void

export extern fn msstd_http_exchange_close(handle: NativeExchange) Void

export extern fn msstd_http_exchange_headers(handle: NativeExchange) move HttpHeaders

export extern fn msstd_http_exchange_method(handle: NativeExchange) move String

export extern fn msstd_http_exchange_path(handle: NativeExchange) move String

export extern fn msstd_http_exchange_protocol(handle: NativeExchange) move String

export extern fn msstd_http_exchange_query(handle: NativeExchange) move String

export extern fn msstd_http_exchange_read(
	handle: NativeExchange,
	max_bytes: Int?,
) move Bytes?!

export extern fn msstd_http_exchange_send_headers(
	handle: NativeExchange,
	status: Int,
	headers: HttpHeaders,
) Void!

export extern fn msstd_http_exchange_send(
	handle: NativeExchange,
	status: Int,
	headers: HttpHeaders,
	body: Bytes,
) Void!

export extern fn msstd_http_exchange_write(handle: NativeExchange, data: String) Void!

export extern fn msstd_http_exchange_write_bytes(
	handle: NativeExchange,
	data: Bytes,
) Void!

export extern fn msstd_http_exchange_upgrade(
	handle: NativeExchange,
	allowed_origins: List[String],
	subprotocols: List[String],
	max_message_bytes: Int?,
) move NativeWebSocket!

export extern fn msstd_http_body_close(handle: NativeResponseBody) Void

export extern fn msstd_http_body_metadata(
	handle: NativeResponseBody
) move HttpResponseMetadata

export extern fn msstd_http_body_read(
	handle: NativeResponseBody,
	max_bytes: Int?,
) move Bytes?!

export extern fn msstd_http_body_read_all(handle: NativeResponseBody) move Bytes!

export extern fn msstd_http_headers_append(
	headers: HttpHeaders,
	name: String,
	value: Bytes,
) Void!

export extern fn msstd_http_headers_values(
	value: HttpHeaders,
	name: String,
) move List[Bytes]?

export extern fn msstd_http_headers_names(value: HttpHeaders) move List[String]

export extern fn msstd_http_headers_remove(value: HttpHeaders, name: String) Bool

export extern fn msstd_http_headers_clone(value: HttpHeaders) move HttpHeaders

export extern fn msstd_http_headers_new() move HttpHeaders

// Limits the scheduler threads the runtime starts to `n` (at least 1).
export extern fn msrt_runtime_set_threads(n: Int) Void

export extern fn msrt_runtime_limit() Int
