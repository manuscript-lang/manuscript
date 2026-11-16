# Allocations per HTTP request

## Summary

- Problem: a keep-alive request to a trivial handler makes 22 heap allocations in the Manuscript server and about none in the C server; allocating and freeing them is 1.7k of the 15.4k instructions per request (11%), and the work around them (copying head bytes into `String`s, building and dropping entries) is more.
- Change: keep the pieces of a request in a pooled `RequestBuf` (head bytes with spans for method, target and fields, and the header table), taken from a per-thread pool when a head completes and returned when the exchange finishes. Nothing is allocated per request in steady state.
- Decision requested: none; no API or behavior change. Handlers see the same `HttpRequest` and `HttpHeaders` values.

## Problem

Measured with callgrind on the server process of `bench/perf/guards/http-request` (10,000 keep-alive requests from a child-process client, `MS_THREADS=1`, one header on the request), allocations per request by call site from the call counts of `__rust_alloc` (18) and `msrt_alloc` (4):

| Site | Allocations |
| --- | --- |
| `h1::parse_request_in`: method and target `String`s | 3 |
| `h1::collect`: name `String` and value `Vec` per field | 2 (2 per header) |
| `target::parse`: path and query `String`s | 2 |
| `Headers::from_received`: entry vector and its `Arc` | 2 |
| `exchange::run`: `Exchange`, `ExSt` pieces | 2 |
| `msstd_http_headers_new`, `msstd_http_exchange_headers`: handle objects | 2 Rust + 2 runtime |
| `Exchange::write_head`: response head buffer | 1 |
| `run_handlers`, `after_read`, `poll_ready`, `finish_grow` | 4 |
| handler glue (`streaming`, `serve.stream`, runtime side) | 2 |

Self cost per request: `__rust_dealloc` 828, `__rust_alloc` 630, `msrt_free` 165, `msrt_alloc` 104, 1.73k together, about 79 per allocation and free. A request with 8 headers adds 14 more allocations (name and value per header). The 0-header and 8-header guard runs are part of stage 1's evidence.

## Measured: a header costs 1.7k, not 100

The guard now sends the six headers a browser or curl sends (`guard-http-request`) beside the one-header request (`guard-http-request-small`). Per request: Manuscript 23.97k and 15.38k; bare C (`server.c`, same requests, one connection, callgrind) 2.47k and 1.86k. Each extra header cost Manuscript about 1.7k and C about 120. Of the 8.6k that five headers added, 2.3k was `canonical_owned` (a per-byte loop that tested every byte against a 15-byte string and validated the finished name as UTF-8 again), 1.2k the per-byte CR/LF check, 0.9k `from_utf8` of values, 0.8k alloc and free, 0.4k sorting entries, 0.7k repeated scans for `Host`, `Expect`, `Connection`, `Content-Length` and `Transfer-Encoding`.

Stage 0 (this PR, no design change): table-driven canonical names, word-at-a-time CR/LF scan, ASCII fast path for UTF-8 checks, one pass over the fields for the questions the server asks. Six-header request 23.97k to 20.68k (-3.3k), one-header 15.38k to 14.96k (-0.4k). The allocation stages below start from there; their per-header share (2 allocations per header, sorting, the entries copy) is what remains of the 1.7k.

## Stage 1 (measured): a request's headers in one buffer, ordered when read

Instead of per-header `String`s and `Vec`s, `Headers` is a `Table`: one buffer holding the head's bytes from the first name to the last value (copied once from the receive buffer) and one slot per field (name and value spans). A received table is raw: slots in arrival order, names as sent. Lookups by name compare case-insensitively across the slots and need nothing built; the canonical, sorted and grouped form that `entries()` shows is built on the first enumeration and kept. A request whose handler reads headers by name, or none, never sorts or canonicalizes. `h1` helpers (`RequestScan`, framing, `keep_alive`) read the raw pairs through a `FieldList` trait, so the HTTP/1 response side and HTTP/2 are unchanged. Per request, 3 allocations instead of 2 per header plus 2.

Guard, instructions per 10,000 requests (server only, `MS_THREADS=1`): six headers 206.18M to 171.07M (-3.5k per request), one header 150.03M to 145.52M (-0.45k). With it, `std::thread::current` (132 per request, one `Arc` clone and drop per native-handle use) gives way to a per-thread counter (-97 per request).

The pooled `RequestBuf` below is not needed for the header table; it remains the plan for the exchange objects (stage 2).

## Design

A per-thread pool of `RequestBuf`, each `{ head: Vec<u8>, slots: Vec<Slot> }`, cleared and not freed when returned:

- Head: when a head is complete the parser copies its bytes once into the `head` of a pooled buffer and records spans (offset and length) for method, target, path, query and each field. Accessors return `&str` or `&[u8]` borrowed from the exchange that owns the buffer.
- Fields: `slots` holds the name span, the value span and a static id for names in a table of common canonical names (`Host`, `Content-Length`, ...). Lookup compares the id, or the span with ASCII case folding for other names. The canonical spelling a handler sees is the static string for known ids and a string built on first read for the others. Values of one name chain through the table in arrival order.
- Ownership and escape: the `RequestBuf` belongs to the `Exchange`. At finish it returns to the pool only when `Rc::strong_count` of the exchange and of the headers handle is 1; a handle a handler kept past the request holds the buffer, which is then dropped normally and the pool allocates a new one. A handler that stores `HttpHeaders` across requests therefore stays correct and only costs the allocation it costs today.
- Threads and HTTP/2: the pool is per thread, so nothing crosses threads: a stolen connection is idle (it holds no `RequestBuf`) and takes one from the new thread's pool at its next head. HTTP/2 takes one `RequestBuf` per stream from the same pool, so concurrent streams do not share storage.
- Exchange and handle objects: `Exchange` and `ExSt` come from the same per-thread pool under the same refcount rule; `HttpHeaders` and the request handle point into the exchange's buffer instead of allocating a handle each (stage 2).
- Response head: written straight into the connection's output buffer (stage 2).

The shape is general: any request, any number of headers, any handler. Nothing is keyed on a header name, a count or the benchmark.

## Components

- `crates/ms-std-net/src/http/h1.rs`, `target.rs`, `headers.rs`, `exchange.rs`, `server.rs`, `server/h2serve.rs` (HTTP/2 builds the same table from decoded fields), `client.rs`, `ffi/http_client.rs`, `ffi/http_server.rs`, `ws/handshake.rs`.
- `Headers` keeps its public methods; `Entry` and `Values` go, so callers of `entries()` iterate `(name, values)` pairs.

## Expected gain

Estimate, to be replaced by guard numbers: 18 of 22 allocations removed at 79 instructions each is about 1.4k, plus part of the copy and drop work of `from_received`, `collect` and the `Headers` drops (about 1.1k of self cost in those functions, overlapping the allocator figure): 1.5k to 2k of the 15.4k, a request with 8 headers more.

## Alternatives considered

- Do nothing: keeps 2,300 instructions of allocator work and the work around it on every request.
- A bump arena reset per request: one allocation per request, but handler values that outlive the request would need a copy; per-connection reuse keeps ownership simple.
- Lazy headers only (earlier experiment, worth 290 when the handler reads none): leaves the per-field `String` and `Vec`, and costs nothing extra to combine with this design.
- Faster allocator fast path: the allocator is already a per-thread free list (about 95 instructions per allocate and free pair here); the saving is in not calling it.

## Staging

1. Head spans, flat table, target spans (parse and headers, about 12 allocations). Stands alone; stages 2 and 3 go ahead only on its measured number.
2. Exchange and handle reuse, response head into the output buffer.
3. Remaining sites: `run_handlers`, `after_read`, `poll_ready`, `finish_grow`, handler glue.

Each stage: the `guard-http-request` count before and after in the PR, and `ms-std-net` tests for 0, 1 and 8 headers read and HTTP/1 and HTTP/2.

## Status (2026-11-16) and open items

Merged: #4218 (allocator), #4260, #4264, #4269 (flat lazy header table, spans from the parse, request buffer reuse), #4277 (reactor poll, Connection scan, event list). Guard `http-request`, server only, 10k requests, callgrind, instructions per request:

| shape | start | now (main 94799fc) | C server |
| --- | --- | --- | --- |
| six headers | 23,965 | 15,824 | ~2,474 |
| one header | 15,378 | 13,740 | ~1,856 |

Self cost per request at the same revision (six headers), ranked; items for a later thread, by owner:

- Parser (kept, httparse): `parse_headers_iter_uninit` 1,160, `match_header_value_vectored` 242, `parse_with_config…` 152. The oracle test `line_ends_found_from_the_parse_agree_with_the_byte_scan` must pass before httparse is bumped.
- Library, open: `RequestScan::of` 543 (one pass per field, six fields), `parse_request_in` 392, `after_read` 389, `from_parsed` 320, `exchange::run` 213, `reactor_task` 248, `write_head` 161, `header_line` 130, `sniff::detect` 122, `target::parse` 175, `read_in` 145. Allocation: `__rust_alloc` 451 and `__rust_dealloc` 506 remain (about 14 sites per request: `target::parse` strings, Pending, `run_handlers`, `after_read`, `request_task`, handle objects). Not done: write the response head straight into the output buffer, and make `finish`/`queue_output`/`write_out` one pass (about 0.6k, 0.5k, 0.44k inclusive).
- Scheduler and reactor, other owners: `swap_ctx` 496, `hibernate_idle` 241, `reactor_wait` 233, `switch_away` 352, `steal_wait_ns` 169, `Poller::poll` 175, `expire_timers` 128, `msrt_task_spawn` 160.
- Generated glue, other owner: `msrt_cleanup_push` 324 and `msrt_cleanup_discard` 187 (registrations for scopes that cannot park need not exist), `serve_buffered` 295, `msrt_string_from_bytes` 145, `from_utf8` 130, `isolate::current` 141, handle objects about 2.1k together.
- Checked and dropped: reordering `list_waiting` checks saves about 5 instructions per request; its 158 is the real work.

Honest floor: library work alone reaches about 13k for six headers; under 10k also needs the glue and scheduler items above.
