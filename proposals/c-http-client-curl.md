# HTTP client on libcurl

## Summary

- Problem: the C client path (own HTTP/1 and HTTP/2 exchanges, 1,360 lines with tests) would still need pooling, redirects, cookies, decompression, proxies and happy eyeballs written and kept correct; the Rust it replaces spends thousands of lines on exactly those (`crates/ms-std-net/src/http/{client,cookies,gunzip,h1,h2client,url}.rs`).
- Change: the standard library's HTTP client calls libcurl through a small native set. libcurl is vendored once as a static archive, HTTP and HTTPS only, on our OpenSSL, nghttp2 and zlib.
- Decision requested: one driver thread running `curl_multi_poll` for all requests, instead of libcurl's socket callbacks on the libuv reactor.

## Status

Approved, 2026-11-20. Chinmay: "for http client, should we just use libcurl?" then "yeah let's do it, we'll not be compiling it every build". Checked against `b65bffcf8`. Replaces the fetch of #4848 (headers and body natives stay).

## Problem

- Verified: `http1_exchange.c`, `http2_exchange.c`, `fetch.c`, `http_client.c` and their tests are 1,360 lines and cover one hop on one dialed row. Redirects, cookies, pooling, gzip, proxies, IPv6 fallback and HTTP/2 stream limits are not there.
- Verified: libcurl 8.16 built HTTP, HTTPS and HTTP/2 only against OpenSSL, nghttp2 and zlib is a 1.5 MB archive (about 0.68 MB of code) and builds in 6 s on 8 cores; it is built once and cached by `runtime/third_party/build.sh`.

## Design

- One process-wide driver thread owns one `CURLM`: its connection cache is the pool, h2 requests to a host multiplex on one connection, DNS is cached. Cost is one thread; a cold DNS lookup uses curl's resolver thread, and proxies from the environment are off so the address check sees the real peer.
- A fetch builds the easy handle on the calling task, hands it to the driver (mutex queue plus `curl_multi_wakeup`) and parks on a token (`msrt_token_new` with flag 1) until the response head arrives. The driver posts it with `msrt_token_post_remote`.
- The body streams: the write callback fills a bounded buffer per transfer (256 KiB) and returns `CURL_WRITEFUNC_PAUSE` when full; `msstd_body_read` takes bytes, parks when empty, and asks the driver to unpause. A task that is cancelled or closes the body unlinks its transfer; nothing else is touched.
- One timeout covers the whole exchange, as before (`CURLOPT_TIMEOUT_MS`). `msstd_body_read_all` has a byte limit.
- Policy in curl: redirects (`max_redirects`, default 20, sensitive headers dropped across origins), cookies (per client, in memory), `Accept-Encoding` with decompression, h1 or h2 by ALPN. Policy in `.ms`: which hosts a `Network` may reach, resolver choice, retries.
- Network restriction: the client takes a flat filter (host names (exact, case-folded) and CIDRs, as in `stdlib/net/policy.ms`) matched in C: the URL host before submit, each `Location` host in the header callback before the hop connects, each address in `CURLOPT_OPENSOCKETFUNCTION`. A refusal ends the request with `STATUS_PERMISSION_DENIED`. A `.ms` callback is not possible: these run on the driver thread, outside any task.
- TLS roots and client certificates are passed in memory (`CURLOPT_CAINFO_BLOB`, `CURLOPT_SSLCERT_BLOB`); no CA path is compiled in.
- Raw connections, TLS dial, DNS and WebSocket stay on the row layer (`ConnH`); curl does not touch them. The server still uses llhttp and nghttp2 directly.

Natives (`ms_rt/net.h`): `msstd_http_client_new(options, out ClientH, err)`, `msstd_http_fetch(client, method, url, headers, body, has_timeout, timeout, out BodyH, err)`, and the existing `msstd_headers_*` and `msstd_body_{read,read_all,metadata,close}`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `runtime/net/curl_client.c` (new) | driver thread, queue, transfer state, callbacks | `curl_client_test`: loopback h1 server: reuse, redirects, cookies, gzip, streaming over 1 MB, cancel, timeout, filter |
| `runtime/net/net_filter.c` (new) | host, suffix and CIDR matching | `net_filter_test` |
| `runtime/net/fetch.c` | URL fetch and body natives on curl | `net_natives_test` |
| `http1_exchange`, `http2_exchange`, `http_client` | deleted | their tests deleted |
| `build.sh`, `c-libs.lock`, `MsLibs.cmake`, `libs.sh` | libcurl pinned, built once, cached by the existing key | `cmake` configure on Linux, macOS, Windows CI |

## Alternatives considered

- Keep our own exchanges and grow them: every feature above is written again, and has to match what curl does for the edge cases (303 method change, 307 body replay, cookie domain rules).
- libcurl socket callbacks on the libuv reactor: the reactor offers per-task readiness (`ms_io_watch`), not persistent callback registrations, so it needs a new reactor primitive for one client. Revisit if the one thread shows up in a profile.
- `curl_easy_perform` on the libuv thread pool: one blocked thread per in-flight request.
- Do nothing: the Rust client stays and Rust cannot be removed.
