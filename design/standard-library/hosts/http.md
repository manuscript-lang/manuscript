+++
title = "HTTP request hosts"
weight = 45
+++

# HTTP request hosts

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The HTTP host gives each request its own execution context and limits. It controls admission, body sizes, deadlines, disconnect cancellation, backpressure, and fault isolation. Handlers use parallel APIs for joined work and `with` for request resources.

If the client disconnects, the host cancels the request and its nested groups. Those groups finish joining and registered cleanup runs before the request ends.

Request handlers use `parallel` or `parallel_map` for joined work and `with` for request resources. Client disconnection cancels the request and its nested groups; those groups join and registered cleanup runs before request execution ends.

Streaming responses remain within their request lifetime until streaming finishes. WebSocket/session hosts establish explicit session lifetimes and participate in shutdown; they are not untracked background goroutines.

Application background services are constructed under the application context and passed to handlers. Accepted work uses that service's context, not the submitting request's deadline or disconnect signal. Jobs capture request data and application services and acquire their own resources. Admission can race with request cancellation; idempotent submissions are an application concern.

Server shutdown stops request admission, allows a configured grace period, cancels and joins remaining request/session work, closes background admission and drains/cancels/joins those services, then releases application resources. A finite grace period does not guarantee uncooperative work exits; host escalation is separate.

## Bounded request API

`@std/http.ms` exports `Network`, `HttpServer`, `HttpRequest`, and `HttpResponse`. The CLI host supplies `process.network: Network`; source cannot manufacture native network authority.

```manuscript
type HttpRequest:
    method: String
    path: String
    query: String
    headers: Map[String, Bytes]
    body: Bytes

type HttpResponse:
    status: Int
    headers: Map[String, String]
    body: Bytes

# Network
fn serve(address: String, handler: fn(request: HttpRequest) -> HttpResponse,
         limit: Int, max_body_bytes: Int, max_response_bytes: Int,
         timeout: Duration, grace: Duration) -> Result[HttpServer, IoError]
fn close() -> Unit

# HttpServer
fn address() -> String
fn wait() -> Result[Unit, IoError]
fn close() -> Unit
```

These signatures specify library operations. A complete declaration places the entire function header inside delimiter continuation. `serve` accepts an ordinary handler, including a function parameter or field, and may be stored as a bound method. `limit` and `timeout` are positive; byte bounds and `grace` are nonnegative. Invalid settings return `IoError.InvalidInput`; binding failure returns `Unavailable`; a closed network returns `Closed`. Port zero permits an OS-selected port reported by `address()`.

The host admits at most `limit` requests; excess requests receive 503 without invoking a handler. Bodies over the bound receive 413. Each handler gets a fixed timeout/disconnect context, and all work and cleanup in it join before its lifetime ends. Handler faults are isolated as 500 and recorded by the bounded diagnostic sink. Timeout/cancellation yields 504 where the connection still permits a response. Source routes by ordinary branching on method/path; raw query remains encoded. Header values are bytes to preserve non-UTF-8 HTTP input. Header keys are visited in sorted order.

Responses require status 200 through 599, a bounded body, and valid header names/values. Content-Length, Transfer-Encoding, and Connection are host-managed and cannot be supplied. Invalid responses yield 500. This API is deliberately a bounded, fully buffered request/response host. [Streaming HTTP and reusable clients](../packages/http.md) and [WebSocket sessions](../packages/websocket.md) have separate implemented contracts.

Server close stops admission, waits up to grace, then cancels and joins remaining requests and closes transport. It cannot be called from its own request. Network close joins all its servers. A server also registers with its construction execution lifetime, so omitting a `with` binding cannot detach server work. Unexpected transport release errors are cleanup faults; uncooperative handlers may delay joining beyond grace.

See [background services](../tasks/background.md), [cancellation](../../concurrency/cancellation.md#propagation-and-checkpoints), and [conformance programs](../../compiler/conformance/programs.md).
