# HTTP server clock reads

## Summary

- The HTTP server reads a clock about 3 times per request on a plain server with no timeout, and 4 to 6 with one; a cached "turn time" cannot fix it (see Alternatives).
- Remove the need for a stamp instead: skip `started` when no timeout is set, give connection timeouts a sweep generation instead of an absolute time, and read the wall clock for `Date` once per reactor turn.
- Decision requested: approve connection timeouts becoming accurate to one sweep interval (timeout / 8) instead of exact.

## Status

Implemented, 2026-11-16, on `main` at 15a1261b. Supersedes the closed #4207 (cached turn time). Review outcome: direction agreed by the lead thread.

## Problem

Measured with an `LD_PRELOAD` counter on `clock_gettime` over 20k requests of `bench/perf/http-tail/server.ms` (no timeout set), outside the idle spin:

- `Pending.started: Instant::now()` in `begin_request`: 1 per request. It is read only when a timeout is set (`exchange.rs`: `deadline`, `late`); otherwise it is dead.
- `Reactor::with_date` reads `SystemTime::now()` on every response: 1 per request.
- `promise::start_on` stamps `Start.at` for the steal beat: 1 per request (scheduler side, not changed here).

With `Limits.timeout` set, each request also stamps `Instant::now() + timeout` for the connection (`server.rs` `add_conn`, idle head, partial head), reads it again in the write loop and in `limit_current_until`, and again in `finish` (`started.elapsed()`).

A cached time is unsound for any of these: code in a request task cannot know how long other tasks ran since the cache was read (#4207 broke `e2e/stdlib/http-request-deadline` this way).

## Design

- **`started` only when needed.** `Pending.started` becomes `Option<Instant>`, set only when `limits.timeout` is `Some`. No timeout: no read.
- **Connection deadlines by generation.** The reactor keeps `generation` and a tick every `timeout / 8` (set by the first timeout that arms it; the tick stops when no connection is left). A connection stores the generation when its idle or head wait started, not `now + timeout`. A tick bumps the generation and sweeps; a connection closes after `timeout.div_ceil(tick) + 1` ticks (not `Busy`, as today). It closes no earlier than `timeout` and at most an eighth after it: a 30 s timeout closes between 30 and 33.75 s. The reactor reads the clock once per turn, only while a tick is running; stamping reads none, except starting the tick clock.
- **No clock in task code.** Activity updates are an integer store. The only clock reads left for deadlines are the sweep's own (one per sweep) and, with a timeout set, the handler limit (below).
- **Handler limit.** `limit_current_until` needs an absolute runtime deadline and stays one read per request when a timeout is set. Making it a sweep count needs runtime support; out of scope, listed in Open questions.
- **Date once per turn (measured: closed loop, 64 connections: 1.67 to 0.39 wall-clock reads per request; at 4000 req/s open loop a turn is one request, so 1 to 1.27).** `Reactor::service` reads the wall clock once after the poller returns and every response written until the next turn uses it. Consequence, stated in the code: `Date` is the time the turn began, so a response written after a handler that ran 10 s carries a `Date` 10 s old. RFC 9110 allows a `Date` at origination; a long handler is where it is least accurate.
- **Exact where promised.** `grace` and rejection drain keep absolute deadlines (once per close, not per request). h2 stream `started` keeps its read (once per stream).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-std-net/src/http/server.rs` | `started` optional, generation field on `ConnSt` and `Reactor`, sweep interval, per-turn date | `http-request-deadline` fixture (200 ms timeout, grace), unit tests: idle close between `timeout` and `2 * timeout`, partial head finished in time stays open |
| `ms-std-net/src/http/exchange.rs` | `started` optional in `deadline`, `late` | same fixture |
| `ms-std-net/src/http/server/steal.rs` | unchanged (owned by the HTTP watcher rewrite): `park` still takes an `Option<Instant>`, which now only flags that the connection is timed; a connection another thread adopts starts its timeout again, so it may wait up to twice the timeout once | steal tests |
| `stdlib/net/http.ms` | `HttpServerOptions.timeout` doc: idle close within an eighth after | `make docs` |

## Alternatives

- Cached turn time with a stale flag (#4207): saved 0.75 reads per request and needed a rule per call site. Rejected.
- Coarse clock (`CLOCK_MONOTONIC_COARSE`): not on macOS or Windows, and 1 to 4 ms resolution; rejected for parity.
- Do nothing: a vDSO read is about 20 ns, so 3 reads is under 0.1 percent of a 0.65 ms request. The change is worth it for the structure (no stamps to go stale), not the nanoseconds.

## Open questions

- Handler request timeout as a sweep count in the runtime (`limit_current`), to drop the last per-request read when a timeout is set.
- Scheduler side: the `start_on` stamp needs a clock for the 20 µs steal beat, and per-switch timer expiry reads the clock only when a timer exists. Both belong to the sleeps thread's redesign; not changed here.
