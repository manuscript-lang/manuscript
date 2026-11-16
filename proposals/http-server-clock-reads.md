# HTTP server clock reads

## Summary

- The HTTP server reads a clock about 3 times per request on a plain server with no timeout, and more with one; a cached "turn time" cannot fix it (see Alternatives).
- Remove the need for a stamp: skip request arrival time when no timeout is set, start a connection's timeout without a time and let the reactor set it at its next clock read, and read the wall clock for `Date` once per reactor turn.
- Timeouts stay exact: a deadline is never early and is late by at most the time to the reactor's next read.

## Status

Implemented, 2026-11-16, on `main` at 15a1261b. Supersedes the closed #4207 (cached turn time) and an earlier tick design in this PR (it fired early after a long handler and added a periodic wake).

## Problem

Measured with an `LD_PRELOAD` counter on `clock_gettime` over 20k requests of `bench/perf/http-tail/server.ms` (no timeout set), outside the idle spin:

- `Pending.started: Instant::now()` in `begin_request`: 1 per request. It is read only when a timeout is set (`exchange.rs`: `deadline`, `late`); otherwise it is dead.
- `Reactor::with_date` reads `SystemTime::now()` on every response: 1 per request.
- `promise::start_on` stamps `Start.at` for the steal beat: 1 per request (scheduler side, not changed here).

With `Limits.timeout` set, each request also stamps `Instant::now() + timeout` for the connection when it goes idle and when its head arrives in pieces.

A cached time is unsound for any of these: code in a request task cannot know how long other tasks ran since the cache was read (#4207 broke `e2e/stdlib/http-request-deadline` this way).

## Design

- **`started` only when needed.** `Pending.started` is `Option<Instant>`, set only when `limits.timeout` is `Some`.
- **Deadline pending.** Where code did `deadline = Instant::now() + timeout`, `Reactor::start_timeout` sets `ConnSt.pending` and pushes the connection's token on `Reactor.pending`. No clock read.
- **Resolved at the next read.** `settle_timeouts` runs right before the reactor parks and after every poll inside `service` (which does not return while the poller always has events, so a saturated reactor still arms and enforces timeouts). If any is pending or a sweep is due it reads the clock, sets `deadline = now + timeout` for each pending connection, and sweeps if due. The read is after the mark, so a deadline is never early, and before the sleep, so it is armed before it. At most two monotonic reads per turn, as on `main`; no periodic wake.
- **Hand-off.** A connection listed for another thread (`list_waiting`: plain HTTP on scheduler threads, timeout set) is resolved with its own read first, so `steal.rs` keeps receiving a real deadline and is unchanged.
- **Date once per turn.** `Reactor::service` reads the wall clock once after the poller returns; every response until the next turn uses it. `Date` is the time the turn began: a response written after a handler that ran 10 s carries a `Date` 10 s old. RFC 9110 allows `Date` at origination.
- **Unchanged.** Handler limit, grace, rejection drain and h2 stream clocks keep their reads (once per request when a timeout is set, once per close, once per stream).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-std-net/src/http/server.rs` | `started` optional, `pending` on `ConnSt`, `Reactor::start_timeout` and `resolve_pending`, one read before parking, per-turn `Date` | `http-request-deadline` fixture; unit tests: idle close between `timeout` and `timeout + 400 ms`, a head sent in pieces within the timeout is answered |
| `ms-std-net/src/http/exchange.rs` | `started` optional in `deadline`, `late` | same fixture |

## Alternatives

- Cached turn time with a stale flag (#4207): saved 0.75 reads per request and was unsound for task code.
- Sweep generations (tick = timeout / 8): no per-request stamp, but a long handler left the generation behind real time so a later connection could close early, and it woke the reactor every tick. Rejected.
- `CLOCK_MONOTONIC_COARSE`: not on macOS or Windows; 1 to 4 ms resolution.
- Do nothing: a vDSO read is about 20 ns against a 0.65 ms request, so the gain is structure, not speed.

## Open questions

- With a timeout set, a request still reads for its arrival time, the hand-off and the handler limit (`limit_current_until` needs an absolute runtime deadline). A runtime limit expressed in the reactor's terms would remove the last one.
- Scheduler side: the `start_on` stamp needs a clock for the 20 µs steal beat, and timer expiry per switch reads the clock only when a timer exists. Both belong to the steal-beat redesign; not changed here.

## Follow-up: scheduler rounds and absolute deadlines

- **Timer check once per round.** `switch_away` checks timers once per pass over the tasks that were ready when the last check ran (`Sched.timer_round`, clamped to the queue length, so a task that blocks ends the round early). A due timer waits at most one round, as a task at the back of the queue does; a lone yielding task is a round of one and checks every switch. No constants. 40000 switches with a timer pending: 1 task 40002 reads, 2 tasks 20002, 64 tasks 627 (was 40000 in each).
- **Absolute deadlines.** `msrt_task_wait_fd_at` and `msrt_token_park_at` take a time on the monotonic clock and `set_deadline` reads no clock; the relative calls convert once. `ms-std-net` `Deadline` holds that time, so a wait reads no clock. `Exchange` hands its request deadline to the waits and to `limit_current_at` as it is.
- **Hand-off after the deadline is set.** `list_waiting` no longer reads the clock to give `steal.rs` a deadline: it waits until `resolve_pending` has set the deadline at the reactor's read and lists the connection then.
- **Still read per request with a timeout** (closed loop, 64 connections, 4.2 per request): the arrival stamp (1, exact; a pending stamp resolved at the reactor's read saved nothing, because handlers of a batch run before it), `late` after the handler (1; a handler that never switches is never killed, so only a read tells it ran past its deadline), the scheduler's per-round check while a kill timer is armed (1), and `settle_timeouts` before the reactor parks (1; it must be a read after the creators it resolves). The queue stamp (`start_on`) waits for the steal-beat work.
