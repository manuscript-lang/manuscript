# Standard fetch client (design proposal)

## Summary

- Problem: `Network.request` and `HttpClient` are complete transports (pooling, redirects, TLS, gzip, cookies, limits), but a plain GET-and-parse-JSON takes a `Network`, a `HttpClientOptions`, a `headers()`, an `HttpMethod`, a `Result` unwrap, a UTF-8 decode, and a `json.parse`.
- Change: a new `@std/net/fetch.ms`, written entirely in Manuscript on top of `@std/net/http.ms`, `@std/net/net.ms`, and `@std/data/json.ms`. One call for the common case, a reusable `Fetcher` for pooling and a restricted network.
- Cost: no Rust, no `bindings.json` change, no new language feature. About 250 lines of `.ms`.
- Decision requested: sign-off on the names and defaults below.

## Status

- Proposal, 2026-10-25, written against `main` at `16291da3`.
- Direction (Chinmay, 2026-10-25): "we also need a standard fetch implementation in manuscript". Project rule: Manuscript first, Rust only for small primitives.

## Problem

- Verified: `stdlib/net.ms` `Network.request` returns a buffered `ClientResponse` with `body: Bytes`. Redirects are not followed, there is no default size limit, and no text or JSON helper.
- Verified: `HttpClient` (`stdlib/http.ms`) follows redirects (`max_redirects`), pools, and decodes gzip, but it returns a streaming `ResponseBody`, so callers write the read loop themselves.
- Non-goals: HTTP/2 push, proxies, multipart builders, retries, a cookie API beyond `HttpClientOptions.cookies`, a new transport.

## Design

Reuse the server's types. `HttpMethod`, `HttpHeaders`, `HttpError`, `Bytes` and `Duration` are exactly the ones `HttpRequest` and `HttpResponse` use, so a handler and a client share vocabulary.

```manuscript
import fetch, FetchOptions, json_body from "@std/net/fetch.ms"

type User:
    name: String

fn load() Result[User, FetchError]:
    let response = try fetch("https://example.com/user/1")
    return read_json[User](response)

fn create(user: User) Result[Int, FetchError]:
    let response = try fetch(
        "https://example.com/users",
        FetchOptions(method: HttpMethod.Post, body: try json_body(user))
    )
    return ok(try response.error_for_status().status)
```

API (all in `@std/net/fetch.ms`):

- `fetch(url, options: Optional[FetchOptions] = none) -> Result[FetchResponse, FetchError]`: one buffered call on a one-shot client, closed before returning.
- `fetcher(network = network(), options = FetchOptions()) -> Result[Fetcher, FetchError]` and `Fetcher.fetch(url, options)` (interface defaults must be `none`, so `options` is `Optional[FetchOptions]`), `Fetcher.stream(url, options) -> Result[ResponseBody, FetchError]`, `Fetcher.close()`. `Fetcher` holds an `HttpClient`, so connections are reused and the `Network`'s restrictions apply to every request and redirect.
- `FetchOptions` fields, all defaulted:
  - `method: HttpMethod = Get`, `headers: Optional[HttpHeaders] = none` (none is empty, so no shared mutable default).
  - `body: FetchBody = FetchBody.Empty`.
  - `timeout: Optional[Duration] = some(seconds(30))` and `max_response_bytes: Optional[Int] = some(16 MiB)`; pass `none` to remove either. A fetch is bounded by default, unlike the raw transport.
  - `FetcherOptions` (client creation): `max_redirects = some(20)`, `decompress = True`, `cookies = False`, `tls`.
- `FetchBody`: `Empty`, `Text(String)`, `Raw(Bytes)`, `Stream(ReadStream)`. `json_body[T](value) -> Result[FetchBody, FetchError]` stringifies with `@std/data/json.ms` and records the `application/json` content type; `fetch` sets `Content-Type` only when the caller's headers lack one (`text/plain; charset=utf-8` for `Text`, `application/octet-stream` for `Raw`).
- `FetchResponse`: `head: HttpResponseMetadata` and `body: Bytes` (the existing `ClientResponse` shape, no third shape), with `ok() -> Bool` (200 to 299), `text() -> Result[String, FetchError]` (UTF-8), `read_json[T](response)` is a free function because source methods cannot declare type parameters. `check_status(response) -> Result[FetchResponse, FetchError]` is a free function that consumes the response (a method cannot return its owned receiver).
- `FetchError`: `Http(HttpError)`, `Io(IoError)`, `Status(code: Int)` (only from `check_status`), `InvalidText`, `Json(JsonError)`; implements `Error`.
- Body drain is written in Manuscript over `ResponseBody.read`: it counts bytes itself and returns `Http(LimitExceeded)` past `max_response_bytes`; a read error after the deadline maps to `Http(Timeout)`, otherwise `Io`. No Rust change.
- Review fixes (skeptic review, 2026-10-25): per-client settings live in `FetcherOptions` (`max_redirects`, `decompress`, `cookies`, `tls`), per-request settings in `FetchOptions`; `fetch` clones caller headers before adding `Content-Type`; `Fetcher.stream` has no default timeout (it is a whole-exchange deadline); a `Stream` body does not follow redirects and `fetch` documents that; `FetchResponse` is not forwardable to a server handler without dropping `Content-Length`/`Connection`, so that claim is removed; HTTP/2 needs `tls.alpn` containing `h2`, left to `FetcherOptions`; `Referer` leak across origins is a transport issue, filed separately.

Semantics:

- Like web `fetch`, a 404 or 500 is an ordinary response: `Err` means no usable response (transport, timeout, limit, permission, closed). `ok()` or `error_for_status()` is the status check.
- Cancellation: a cancelled task cancels the in-flight request through the transport; `Fetcher.close()` cancels every request in flight and later calls return `Http(Closed)`.
- Security: the transport already refuses HTTPS-to-HTTP redirects, user info in URLs, and destinations the `Network` disallows. `fetch` adds no override.
- Ownership: `FetchResponse` owns its `Bytes` and a cloned `HttpHeaders`; `text` and `json` borrow `body`.
- Streaming is on `Fetcher.stream` only, so the one-call `fetch` always has a size bound.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/fetch.ms` | new module | e2e fixtures below |
| `stdlib/http.ms`, `net.ms`, `bindings.json`, `crates/*` | unchanged | existing |
| `tests/e2e/testdata/stdlib/fetch.ms` | local `serve` server: GET text, JSON round trip, POST body, redirect follow and limit, 404 is ok-response, size limit, timeout, `Fetcher` reuse, restricted network denial | `cargo nextest` e2e |
| `ms-conform` harvest list | add `fetch` to the sockets-hostile imports | conformance corpus |
| Docs | module guide comment block in `fetch.ms`; `make docs` generates the reference | `make docs` |
| Formatter, lint, LSP, CLI | unchanged | none |

## Alternatives

- Do nothing: the transport already works, but every caller re-writes the same 10 lines and forgets limits and timeouts (the raw defaults are unbounded).
- Put the helpers on `Network` and `ClientResponse`: grows two core interfaces that the server and many tests implement or consume; a separate module costs nothing for programs that do not import it.
- Rust-side `fetch` primitive: duplicates redirect, TLS, and gzip logic that `ms-std-net` already has, against the Manuscript-first rule.
- Return an error for non-2xx (Go's `http.Get` does not, Rust's `reqwest::get` does not, JS `fetch` does not): rejected; `error_for_status()` makes it one call.

## Staging and verification

- Stage 1 (one PR): `fetch.ms`, e2e tests, harvest-list entry, docs. Go/no-go: `make verify` and the e2e fixture green on Linux, macOS, Windows.
- Stage 2 (later, only if wanted): `fetch` on a request-scope handle once TaskGroup request scopes land, so a handler's cancellation reaches outbound calls.

## Open questions

- Default limits (30 s, 16 MiB, 20 redirects): recommended as proposed; `none` opts out.
