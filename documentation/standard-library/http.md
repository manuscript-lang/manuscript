+++
title = "HTTP"
weight = 16
+++

# HTTP

API reference: [HTTP](reference/http.md) and [Network](reference/net.md).

Use HttpClient for reusable outbound requests and HttpExchange for streaming request handling. Response bodies are resources: read them in chunks and close them. A received HTTP error status is still a response you can inspect.

## Protocols

`Network.serve` invokes a handler with a buffered `HttpRequest` and emits its `HttpResponse`. `Network.request` buffers the response into `ClientResponse`. `HttpClient.send` and `send_stream` return a scoped `ResponseBody`; its status and headers are methods, and its body is read incrementally. Streaming servers receive `HttpExchange`. TLS-enabled reusable clients and streaming servers support HTTP/1.1 and HTTP/2.

## Configuration

Limits and deadlines are optional. Supplied redirect counts, idle capacity, byte budgets, deadlines, and grace must be nonnegative; supplied header and request-admission caps must be positive. `HttpServerOptions` requires an explicit `tls` field: `tls: none` selects plain HTTP/1.1. With TLS configured, native ALPN negotiation selects HTTP/1.1 or HTTP/2. Credentials/trust come from explicit TlsOptions. Client `decompress`, `cookies`, and `tls` settings remain required. No ambient HTTP proxy is read.

### Client lifetime

Create a shared HttpClient through `Network.http_client`. It implements Closeable, so keep it in a `with` scope. It owns a pooled transport and optional public-suffix-aware cookie jar. Idle connections and lifetime are explicit options. Close stops admission, cancels in-flight requests, closes outstanding response bodies, joins their upload/read work and releases idle connections. Network close owns and joins clients too.

### Reading a response

`send` returns a ResponseBody that you read incrementally. Reads follow the stream contract. `max_response_bytes` limits the cumulative decoded output. Status and duplicate headers remain available as metadata. Close before EOF cancels/discards the body; consumed bodies can reuse the pooled connection. Timeout covers DNS through body lifetime; parent cancellation unwinds. Gzip decoding is enabled only with decompress and remains subject to the expanded-byte bound. Invalid UTF-8 header values are rejected before constructing source Strings.

### Streaming an upload

Send_stream borrows an explicitly shared ReadStream for the upload and does not close it. The response owns the upload work until response closure/completion: keep the input's scope open through the response scope. Under HTTP/1.1, streaming server responses enable full duplex so a response does not silently drain/close the outstanding upload. Upload faults retain source fault identity, not a generic transport success. Redirects requiring replay are returned to the caller for streaming bodies; immutable Bytes sends can follow configured redirects. A consumed prefix cannot be rolled back after failure.

### Redirects and HTTP status

Redirects honor max_redirects (zero returns the redirect response), reject TLS downgrade, recheck the Network policy on every destination, and remove explicit Authorization/Cookie/Proxy-Authorization when the origin changes. Automatic cookies are selected by the destination jar rather than copying source-origin headers. HTTP 4xx and 5xx statuses are returned responses, rather than transport errors. Header names/values reject injection and callers cannot set host-managed framing fields.

## Request API

`Network` and `network()` are exported by `@std/net.ms`. Buffered request/response records, streaming exchanges, and server types live in `@std/http.ms`.

`Network.serve` accepts `fn(request: HttpRequest) -> HttpResponse` and returns a scoped HttpServer. Request headers are bytes, the raw query stays encoded, and source code routes by ordinary method/path branching. Both server forms validate the original decoded path's UTF-8 before normalization, reject encoded slash (`%2F`, either case) or NUL with 400, then resolve dot segments (including `%2e%2e`) and repeated slashes while preserving a trailing slash. Decoding happens once: `/a%252Fb` reaches the handler as `/a%2Fb`, and handlers must not decode it again. Query escapes stay unchanged. These URL rules do not make filesystem joins a sandbox. Responses require status 200–599, valid header names and values, and a body within any supplied response budget. See [the Network reference](reference/net.md#network) for its exact optional admission, byte, deadline, and grace parameters.

Client disconnection cancels the request and nested task-group work. Started work joins and registered cleanup runs before the request ends. Handler faults become 500 responses and reach diagnostics; deadline expiry produces 504 where the transport permits it. Oversized buffered request bodies receive 413, and excess admission under a supplied cap receives 503 without invoking a handler.

Schedulers used by handlers retain their construction lifetime. Accepted work uses that scheduler's context rather than the submitting request's deadline or disconnect signal. Construct shared schedulers outside request scopes, keep their dependencies open, and acquire operation resources inside each callback. Close them before releasing application resources.

## Header lookup and repeated values

HTTP header names are case-insensitive. Received maps retain canonical spelling such as `Content-Type`; ordinary `Map.get` uses exact, case-sensitive keys. For a buffered request, use `request.header("content-type")` (or `request.header(name: "CONTENT-TYPE")`) to obtain `Optional[Bytes]` without changing the map. A present empty value returns `some` empty bytes; a missing name returns `none`. The helper compares ASCII letters without regard to case. In a manually constructed map containing several equivalent names, the first entry wins.

| API | Header representation | Repeated values |
| --- | --- | --- |
| `HttpRequest.headers` | `Map[String, Bytes]` | Received values are joined with newline bytes. `header` returns those same bytes. |
| `HttpResponse.headers` and outbound client request headers | `Map[String, String]` | One value per exact Map key. Case-equivalent keys emit separate fields in Map insertion order. |
| `ClientResponse.headers`, `ResponseBody.headers()`, `HttpExchange.headers()` and `HttpExchange.send_headers` | `Map[String, List[String]]` | Separate values retain their order within each name. Sending case-equivalent keys appends their lists in Map insertion order. |

Sending `x-dup: first` and `X-Dup: second` emits both values in that order; reversing insertion order reverses the fields without losing either value. `Set-Cookie` fields remain separate, including cookies with commas in `Expires`. Do not comma-join cookies. Received map keys are sorted by canonical name for stable iteration; values retain wire order within a name. There is no ordering guarantee between different names.

Use `Network.serve_stream` and `HttpExchange.send_headers` with a list of cookie strings for arbitrary numbers of repeated response fields. A list-valued header map can be passed directly to `send_headers` after removing host-managed framing fields. Converting it to `Map[String, String]` by taking the first or last value loses data; changing every API to one header type requires a separate migration.

Use `HttpExchange.headers()` when incoming values must remain separate. For a received buffered request, `request.header(name)` returns newline-joined bytes: decode with `Bytes.to_text()` and handle `none` for invalid UTF-8 before splitting on `"\n"`. HTTP values cannot contain newline bytes, so this preserves received empty and repeated fields. Manually constructed records can contain arbitrary bytes and do not establish that wire invariant. Buffered input retains non-UTF-8 bytes; streaming input rejects them with 400, and clients return `HttpError.InvalidData` for non-UTF-8 response metadata.

For any list-valued HTTP map, import `header_values` from `@std/http.ms` and call `header_values(headers: response.headers, name: "set-cookie")` (or pass `body.headers()` / `exchange.headers()`). Lookup folds ASCII letters and concatenates every equivalent entry in Map insertion order, preserving each list's order and empty strings. A missing name returns `none`; a present empty list returns `some` empty list. The returned list has separate membership, so mutating it leaves the input lists unchanged. The helper does not validate or split values, and does not comma-join cookies. Ordinary `Map.get` remains exact and case-sensitive.

Outgoing names must be ASCII HTTP tokens; values must be valid UTF-8 without control bytes except tab. CR, LF, NUL, and DEL are invalid. Both server forms validate the entire header map before emitting caller fields. An invalid buffered response becomes 500; invalid client headers or `send_headers` return `HttpError.InvalidInput`. Clients reject `Host`, `Content-Length`, and `Transfer-Encoding`; servers reject `Content-Length`, `Transfer-Encoding`, and `Connection` regardless of casing.

## Error boundaries

`request`, `http_client`, `send`, `send_stream`, `serve_stream`, and `send_headers` use `HttpError`. Buffered `serve` and `HttpServer.wait` use `IoError`. Streaming body reads and exchange reads/writes also use `IoError`, while upgrades use `WebSocketError`. These retain their domain error types; use an explicit match or a compatible `Error` boundary when composing operations. Buffered admission is named `limit`; the equivalent streaming option is `max_requests`.

## Streaming request servers

Network.serve_stream accepts an ordinary handler and may be stored as a bound method. The handler signature is `fn(exchange: HttpExchange) -> Result[Unit, HttpError]`. The server establishes a fixed request execution context, optional admission and body/output/header budgets, disconnect cancellation, and an optional timeout. The handler may read incrementally, emit headers once and write/flush bounded output, or upgrade to a WebSocket session. Source routes by ordinary method/path branching.

### Response ordering and limits

Read and write have separate synchronized gates. Send_headers accepts status 200–599 and ordered duplicate header values; it rejects repeated headers emission, CR/LF/NUL values, and caller-supplied framing. Write requires headers first, counts cumulative output bytes, applies native backpressure and disallows bodies for HEAD/204/304. Body bound failures return IoError.Failed with a limit diagnostic. Before headers, handler faults/domain errors produce a generic 500, or 504 for timeout where possible; after headers the host aborts transport rather than returning a misleading complete body. Returning success without headers produces 204.

### Request and server lifetime

HttpExchange belongs to its request: retained aliases report Closed once request cleanup ends. Server shutdown stops admission, waits grace, cancels remaining requests/sessions and joins them before returning. Hijacked WebSocket transports are explicitly included in request cleanup and joining. A server or Network cannot close from its own handler. Streaming source code needs no new function kind or detached task syntax.
