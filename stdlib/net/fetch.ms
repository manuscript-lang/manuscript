// Fetch-style HTTP client implemented in Manuscript over `@std/net/http.ms` and
// `@std/data/json.ms`.
import (
	Bytes from "@std/bytes.ms",
	Placement, Promise, PromiseOptions, promise from "@std/concurrency/promise.ms",
	Closeable, Data from "@std/core.ms",
	JsonOptions, parse, stringify from "@std/data/json.ms",
	HttpClient,
	HttpClientOptions,
	HttpHeaders,
	HttpMethod,
	HttpResponseMetadata,
	NativeHttpClient,
	RawResponse,
	StreamingResponse,
	headers from "@std/net/http.ms",
	Network, http_client from "@std/net/net.ms",
	TlsOptions from "@std/net/tls.ms",
	Duration, Instant, monotonic, seconds from "@std/time.ms",

	msstd_http_client_request_bytes,
	msstd_http_client_share from "@std/internal/http.ms",
)

// The request body: empty, text, raw bytes, or JSON text; `fetch` derives a default
// `Content-Type` from the case.
export enum FetchBody:
	// Sends no body and no default `Content-Type`.
	Empty
	// UTF-8 text, sent as `text/plain; charset=utf-8` unless a `Content-Type` is given.
	Text(
		// The text, sent as UTF-8 bytes.
		value: String
	)
	// Raw bytes, sent as `application/octet-stream` unless a `Content-Type` is given.
	Raw(
		// The bytes, sent unchanged; the value is cloned per request.
		value: Bytes
	)
	// JSON text produced by `json_body`.
	JsonText(
		// The encoded JSON text, sent as UTF-8 bytes.
		value: String
	)

// Encodes `value` as a JSON request body, sent as `application/json` unless a
// `Content-Type` is given.
export fn json_body[T: Data](value: T) FetchBody!:
	text := stringify(value)?
	return ok(FetchBody.JsonText(text))

// Per-request settings. Every field has a default, so `FetchOptions()` (the default) is
// a plain GET with a 30 second deadline and a 16 MiB response cap; set only the fields
// that differ, as in `FetchOptions(method: HttpMethod.Post)`.
export type FetchOptions:
	// The request method; defaults to Get. Extension tokens use the Custom case.
	method: HttpMethod = HttpMethod.Get
	// Extra request headers; none sends no extra fields. The caller's headers are never
	// modified.
	headers: HttpHeaders?
	// The request body; defaults to Empty. A Text, Raw, or JSON body adds a
	// `Content-Type` only when `headers` lacks one.
	body: FetchBody = FetchBody.Empty
	// Whole-exchange deadline; none waits without limit.
	timeout: Duration? = seconds(30)
	// Largest accepted response body in bytes; none sets no cap. Larger bodies return
	// `EOVERFLOW`.
	max_response_bytes: Int? = 16777216

// Settings fixed when a `Fetcher` is created.
export type FetcherOptions:
	// Most redirects followed per request; 0 returns the redirect itself and none sets
	// no cap.
	max_redirects: Int? = 20
	// Decode gzip responses, bounded by `max_response_bytes`.
	decompress: Bool = true
	// Keep an in-memory cookie jar for the fetcher's lifetime.
	cookies: Bool = false
	// TLS trust and client-certificate settings; add `h2` to `alpn` to allow HTTP/2.
	tls: TlsOptions = TlsOptions(
		server_name: "",
		roots_pem: "",
		certificate_pem: "",
		private_key_pem: "",
		alpn: [],
		require_client_certificate: false,
	)

// A buffered response. Error statuses are ordinary responses; use `check_status` to
// reject them.
export type FetchResponse:
	// Status, headers, and protocol.
	head: HttpResponseMetadata
	// The complete body, within the request's `max_response_bytes`.
	body: Bytes

// Returns whether the status is 200 through 299.
fn FetchResponse.ok() Bool:
	return self.head.status >= 200 and self.head.status < 300

// Decodes the body as UTF-8.
fn FetchResponse.text() String!:
	if text := self.body.decode_utf8(): return ok(text)
	return error(Error("fetch: body is not valid UTF-8", kind: "EBADMSG"))

// Decodes the body as JSON into `T`, as in `response.json[User]()?`; use
// `JsonValue` for untyped data.
fn FetchResponse.json[T: Data](ignore_unknown_fields: Bool = true) T!:
	text := self.text()?
	return parse[T](text, JsonOptions(ignore_unknown_fields: ignore_unknown_fields))

// Succeeds when the status is 200 through 299 and otherwise returns `Status`, so
// `response.check_status()?` rejects error responses.
fn FetchResponse.check_status() Unit!:
	if self.ok(): return ok(unit)
	return error(
		Error(
			"fetch: unexpected status {self.head.status}",
			kind: "EIO",
			details: {"status": self.head.status.to_string()},
		)
	)

// A reusable client with connection pooling. Bind it to a local and its scope closes
// it, or close it when done.
export type Fetcher:
	// Internal state: the pooled HTTP client every request goes through.
	client: HttpClient

// Sends the request and buffers the response body. A `Raw` or `Text` body is resent
// on redirects that keep it. Returns the promise of the response; requests started
// together are in flight together.
fn Fetcher.fetch(
	url: String,
	options: FetchOptions = FetchOptions(),
) Promise[FetchResponse]:
	native := msstd_http_client_share(self.client.native)
	owned_url := url.clone()
	owned_options := options.clone()
	return promise(
		fn: sent(native, owned_url, owned_options),
		options: PromiseOptions(placement: Placement.Here)
	)

// Sends the request and returns the streaming body. `options.timeout` is a
// whole-exchange deadline, so set it to none for long streams.
fn Fetcher.stream(
	url: String,
	options: FetchOptions = FetchOptions(),
) StreamingResponse!:
	sent := outgoing(options)
	return self.client.request(
		options.method.clone(),
		url,
		sent.headers,
		sent.body,
		options.max_response_bytes,
		options.timeout,
	)

// Cancels in-flight requests and drops pooled connections; later calls return
// `EBADF`.
fn var Fetcher.close() Unit!:
	return self.client.close()

// Reads the body to its end within the options' size limit, then closes it.
fn drain(body: RawResponse, options: FetchOptions, started: Instant) FetchResponse!:
	open := body
	metadata := open.metadata()
	whole := (
		open
		.read_all()
		.map_error(fn cause: read_failure(cause, options, started))?
	)
	if limit_exceeded(options.max_response_bytes, whole.length()):
		return error(Error("HTTP: limit exceeded", kind: "EOVERFLOW"))

	return ok(FetchResponse(head: metadata, body: whole))

// Maps a body read failure to a fetch error, reporting ETIMEDOUT once the deadline has
// passed.
fn read_failure(cause: Error, options: FetchOptions, started: Instant) Error:
	if expired(options.timeout, started):
		return Error("HTTP: operation timed out", kind: "ETIMEDOUT")
	return cause.clone()

type Outgoing:
	headers: HttpHeaders
	body: Bytes

fn limit_exceeded(limit: Int?, total: Int) Bool:
	if max := limit: return total > max
	return false

fn expired(timeout: Duration?, started: Instant) Bool:
	if limit := timeout: return monotonic().difference(started).compare(limit) >= 0
	return false

// Copies the caller's headers and adds a default `Content-Type` for the body.
fn outgoing(options: FetchOptions) Outgoing:
	var fields = headers()
	if given := options.headers:
		fields = given.clone()

	var kind = ""
	var data = "".to_bytes()

	match options.body:
		Empty: kind = ""
		Text(value):
			kind = "text/plain; charset=utf-8"
			data = value.to_bytes()
		Raw(value):
			kind = "application/octet-stream"
			data = value.clone()
		JsonText(value):
			kind = "application/json"
			data = value.to_bytes()

	if kind != "" and not fields.contains("Content-Type"):
		_ignored := fields.append("Content-Type", kind)
	return Outgoing(headers: fields, body: data)

// Creates a reusable fetcher on `net`, whose restrictions apply to every request and
// redirect; none uses the host network.
// ms: effect std.net.connect
export fn fetcher(
	options: FetcherOptions = FetcherOptions(),
	net: Network? = none,
) Fetcher!:
	settings := HttpClientOptions(
		max_redirects: options.max_redirects,
		decompress: options.decompress,
		cookies: options.cookies,
		tls: options.tls.clone(),
	)

	if restricted := net:
		client := restricted.http_client(settings)?
		return ok(Fetcher(client: client))

	client := http_client(settings)?
	return ok(Fetcher(client: client))

// Starts one buffered request on a one-shot client and returns its promise; requests
// started together are in flight together. Redirects are followed up to 20 times, the
// body is limited to 16 MiB, and the exchange to 30 seconds; override them in
// `options`.
// ms: effect std.net.connect
export fn fetch(
	url: String,
	options: FetchOptions = FetchOptions(),
) Promise[FetchResponse]:
	owned_url := url.clone()
	owned_options := options.clone()
	return promise(
		fn: fetched(owned_url, owned_options),
		options: PromiseOptions(placement: Placement.Here)
	)

fn fetched(url: String, options: FetchOptions) FetchResponse!:
	client := fetcher()?
	return sent(client.client.native, url, options)

// Sends the request on the pooled client behind `native` and buffers the response body.
fn sent(native: NativeHttpClient, url: String, options: FetchOptions) FetchResponse!:
	started := monotonic()
	outbound := outgoing(options.clone())
	body := msstd_http_client_request_bytes(
		native,
		options.method.text(),
		url,
		outbound.headers,
		outbound.body,
		options.max_response_bytes,
		options.timeout,
	)?
	return drain(body, options, started)
