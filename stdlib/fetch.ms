# Fetch-style HTTP client implemented in Manuscript over `@std/http.ms` and `@std/json.ms`.
import Bytes from "@std/bytes.ms"
import Closeable, Data from "@std/core.ms"
import (
    HttpClient,
    HttpClientOptions,
    HttpError,
    HttpHeaders,
    HttpMethod,
    HttpResponseMetadata,
    ResponseBody,
    headers
) from "@std/http.ms"
import IoError from "@std/io.ms"
import JsonError, parse, stringify from "@std/json.ms"
import Network, TlsOptions, network from "@std/net.ms"
import Duration, Instant, clock, seconds from "@std/time.ms"

# Errors returned by fetch operations.
export type FetchError:
    # No usable response: invalid URL, transport or TLS failure, timeout, size limit, permission, or a closed client.
    case Http(
        # The transport error; `Timeout`, `LimitExceeded`, and `Closed` report deadline, size-cap, and closed-client failures.
        cause: HttpError
    )
    # Reading the response body failed.
    case Io(
        # The error returned by reading the response body stream.
        cause: IoError
    )
    # `check_status` found a status outside 200 through 299.
    case Status(
        # The received status code.
        code: Int
    )
    # The response body is not valid UTF-8.
    case InvalidText
    # The request or response JSON could not be encoded or decoded.
    case Json(
        # The JSON error from encoding the request body or decoding the response.
        cause: JsonError
    )

impl Error for FetchError:
    # Returns a fixed diagnostic, or the cause's message for wrapped errors.
    fn message() String:
        match self:
            Http(cause): return cause.message()
            Io(cause): return cause.message()
            Status(code): return "fetch: unexpected status {code}"
            InvalidText: return "fetch: body is not valid UTF-8"
            Json(_): return "fetch: invalid JSON"

# The request body: empty, text, raw bytes, or JSON text; `fetch` derives a default `Content-Type` from the case.
export type FetchBody:
    # Sends no body and no default `Content-Type`.
    case Empty
    # UTF-8 text, sent as `text/plain; charset=utf-8` unless a `Content-Type` is given.
    case Text(
        # The text, sent as UTF-8 bytes.
        value: String
    )
    # Raw bytes, sent as `application/octet-stream` unless a `Content-Type` is given.
    case Raw(
        # The bytes, sent unchanged; the value is cloned per request.
        value: Bytes
    )
    # JSON text produced by `json_body`.
    case JsonText(
        # The encoded JSON text, sent as UTF-8 bytes.
        value: String
    )

# Encodes `value` as a JSON request body, sent as `application/json` unless a `Content-Type` is given.
export fn json_body[T: Data](value: T) Result[FetchBody, FetchError]:
    let text = try stringify(value).map_error(json_failure)
    return ok(FetchBody.JsonText(text))

# Per-request settings. Every field has a default, so `FetchOptions()` (the default) is a plain GET with a 30 second deadline and a 16 MiB response cap; set only the fields that differ, as in `FetchOptions(method: HttpMethod.Post)`.
export type FetchOptions:
    # The request method; defaults to Get. Extension tokens use the Custom case.
    method: HttpMethod = HttpMethod.Get
    # Extra request headers; none sends no extra fields. The caller's headers are never modified.
    headers: HttpHeaders?
    # The request body; defaults to Empty. A Text, Raw, or JSON body adds a `Content-Type` only when `headers` lacks one.
    body: FetchBody = FetchBody.Empty
    # Whole-exchange deadline; none waits without limit.
    timeout: Duration? = seconds(30)
    # Largest accepted response body in bytes; none sets no cap. Larger bodies return `Http(LimitExceeded)`.
    max_response_bytes: Int? = 16777216

# Settings fixed when a `Fetcher` is created.
export type FetcherOptions:
    # Most redirects followed per request; 0 returns the redirect itself and none sets no cap.
    max_redirects: Int? = 20
    # Decode gzip responses, bounded by `max_response_bytes`.
    decompress: Bool = true
    # Keep an in-memory cookie jar for the fetcher's lifetime.
    cookies: Bool = false
    # TLS trust and client-certificate settings; add `h2` to `alpn` to allow HTTP/2.
    tls: TlsOptions = TlsOptions(
        server_name: "", roots_pem: "", certificate_pem: "", private_key_pem: "",
        alpn: [], require_client_certificate: false
    )

# A buffered response. Error statuses are ordinary responses; use `check_status` to reject them.
export type FetchResponse:
    # Status, headers, and protocol.
    head: HttpResponseMetadata
    # The complete body, within the request's `max_response_bytes`.
    body: Bytes

impl FetchResponse:
    # Returns whether the status is 200 through 299.
    fn ok() Bool:
        return self.head.status >= 200 and self.head.status < 300

    # Decodes the body as UTF-8.
    fn text() Result[String, FetchError]:
        if let text = self.body.decode_utf8():
            return ok(text)

        return error(FetchError.InvalidText)

    # Decodes the body as JSON into `T`, as in `try response.json[User]()`; use `JsonValue` for untyped data.
    fn json[T: Data](ignore_unknown_fields: Bool = true) Result[T, FetchError]:
        let text = try self.text()
        return parse[T](text, ignore_unknown_fields: ignore_unknown_fields).map_error(
            json_failure
        )

    # Succeeds when the status is 200 through 299 and otherwise returns `Status`, so `try response.check_status()` rejects error responses.
    fn check_status() Result[Unit, FetchError]:
        if self.ok(): return ok(unit)

        return error(FetchError.Status(self.head.status))

# A reusable client with connection pooling. Bind it to a local and its scope closes it, or close it when done.
export type Fetcher:
    # Internal state: the pooled HTTP client every request goes through.
    client: HttpClient

impl Fetcher:
    # Sends the request and buffers the response body.
    # A `Raw` or `Text` body is resent on redirects that keep it.
    fn fetch(
        url: String,
        options: FetchOptions = FetchOptions()
    ) Result[FetchResponse, FetchError]:
        let started = clock().now()
        let body = try self.stream(url, options.clone())
        return drain(body, options, started)

    # Sends the request and returns the streaming body. `options.timeout` is a whole-exchange deadline, so set it to none for long streams.
    fn stream(
        url: String,
        options: FetchOptions = FetchOptions()
    ) Result[ResponseBody, FetchError]:
        let sent = outgoing(options)
        return self.client.request_bytes(
            options.method.clone(), url, sent.headers, sent.body,
            options.max_response_bytes, options.timeout
        ).map_error(http_failure)

impl Closeable for Fetcher:
    # Cancels in-flight requests and drops pooled connections; later calls return `Http(Closed)`.
    var fn close() Unit:
        self.client.close()

# Reads the body to its end within the options' size limit, then closes it.
fn drain(
    body: ResponseBody,
    options: FetchOptions,
    started: Instant
) Result[FetchResponse, FetchError]:
    let open = body
    let metadata = open.metadata()
    let whole = (
        try open
        .read_all()
        .map_error(fn cause: read_failure(cause, options, started))
    )
    if limit_exceeded(options.max_response_bytes, whole.length()):
        return error(FetchError.Http(HttpError.LimitExceeded))

    return ok(FetchResponse(head: metadata, body: whole))

# Maps a body read failure to a fetch error, reporting Timeout once the deadline has passed.
fn read_failure(cause: IoError, options: FetchOptions, started: Instant) FetchError:
    if expired(options.timeout, started):
        return FetchError.Http(HttpError.Timeout)

    return FetchError.Io(cause)

fn json_failure(cause: JsonError) FetchError:
    return FetchError.Json(cause)

fn io_failure(cause: IoError) FetchError:
    return FetchError.Io(cause)

fn http_failure(cause: HttpError) FetchError:
    return FetchError.Http(cause)

type Outgoing:
    headers: HttpHeaders
    body: Bytes

fn limit_exceeded(limit: Int?, total: Int) Bool:
    if let max = limit:
        return total > max

    return false

fn expired(timeout: Duration?, started: Instant) Bool:
    if let limit = timeout:
        return clock().now().difference(started).compare(limit) >= 0

    return false

# Copies the caller's headers and adds a default `Content-Type` for the body.
fn outgoing(options: FetchOptions) Outgoing:
    var fields = headers()
    if let given = options.headers:
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
        let _ignored = fields.append("Content-Type", kind)
    return Outgoing(headers: fields, body: data)

# Creates a reusable fetcher on `net`, whose restrictions apply to every request and redirect.
export fn fetcher(
    options: FetcherOptions = FetcherOptions(),
    net: Network = network()
) Result[Fetcher, FetchError]:
    let settings = HttpClientOptions(
        max_redirects: options.max_redirects, decompress: options.decompress,
        cookies: options.cookies, tls: options.tls.clone()
    )
    let client = try net.http_client(settings).map_error(http_failure)
    return ok(Fetcher(client: client))

# Performs one buffered request on a one-shot client.
# Redirects are followed up to 20 times, the body is limited to 16 MiB, and the exchange to 30 seconds; override them in `options`.
export fn fetch(
    url: String,
    options: FetchOptions = FetchOptions()
) Result[FetchResponse, FetchError]:
    let client = try fetcher()
    return client.fetch(url, options)
