# Connection stealing in the C scheduler

## Summary

- Problem: a handler that computes without a wait holds its scheduler thread, so requests on that thread's other idle connections wait for it; the Rust watcher and `steal.rs` fix this, and the C scheduler has neither.
- Change: port the recorded design to C. A watcher thread in `runtime/core` sees a thread that has not turned its reactor for a look and tells a resting thread to take that thread's waiting connections; the C server keeps the list of waiting connections. Tasks never move.
- Decision requested: none; no API, language or default change.

## Status

Proposal, 2026-11-20; stage 1 merged (#5080); stage 2 builds the idle pool the HTTP/2 thread asked for. Keeps the recorded decisions of the wiki page `a-computing-handler-holds-its-thread-so-idle-connections-are-taken.md`: connections move and tasks do not (Chinmay, 2026-11-15); the watcher keeps its periodic look and both latencies (Chinmay, 2026-11-16). Review: an independent reviewer found the task-free premise unmet by today's `runtime/net` and four missing pieces (below); the design now states them.

## Problem

- The fixture `tests/conformance/fixtures/e2e/stdlib/http-long-handler-does-not-hold-others.ms`: one handler spins 400 ms; requests on three other connections of that thread must still be answered, by another thread. A C server without stealing answers them after 400 ms (p99 rose to the handler time before the Rust fix).
- The idle fixture `http-idle-server-stays-asleep` must keep its limits: under 40 context switches and under 100 ms CPU a second.

## Design

- Watcher (`runtime/core/watch.c`, replaces `crates/ms-rt/src/watch.rs`): one thread, started by the first `ms_watch_add_hook`. It keeps an epoch in ticks of 100 µs, looks every 2 ms (20 ticks) while any scheduler thread is awake and every tick for 0.1 s after a hook says a thread was held up 1 ms, and sleeps after 20 looks with every thread resting. It reads atomics only and never touches a task.
- Turn marks: `ms_park_poll` stores the epoch into the thread's `seen` after each wait returns (one relaxed store per reactor turn); `ms_isolate_idle_leave` stores it into `stirred` and wakes a sleeping watcher. A thread is held up when it is not resting and `max(seen, stirred)` is older than the previous look.
- Hook: `typedef bool (*MsWatchHook)(MsWatchLook look, uint64_t resting)`. The C server registers one; it looks at its group, and for a held-up member with waiting connections sends a resting member isolate mail "take" (`ms_isolate_post`, which wakes its poller).
- Idle pool (`runtime/net/idle.{c,h}`, stage 2, agreed with the HTTP/2 thread, which keeps `serve.ms`): a connection between HTTP/1 requests has no task. After a keep-alive response `serve_h1` calls `msstd_idle_park(conn, head_limit, timeout)` and its task ends; the pool owns a row (connection id, fd, deadline, owner isolate) and the request task, not a connection task, is the unit. Rows use what the scheduler already has for promises: `ms_sched_fd_wait_begin(row, fd, READ)` and `ms_sched_arm(row, deadline)`; ids with a pool tag are routed from `fd_ready`, `timer_live` and `timer_fire` of the promise table to the pool. When the fd is readable the pool spawns a short task on that thread that reads the head (`msstd_xchg_next`, which no longer parks long), calls `msstd_handler_call`, and parks again or closes. Deadline expiry closes the row; `msstd_idle_drain` closes idle rows at once and lets in-flight requests finish within the grace. HTTP/2 stays a task per connection.
- Taking: the waiting list is the pool's rows. A held-up thread's rows are taken by a resting thread: it duplicates the fd under the list lock (`dup`; `WSADuplicateSocket` on Windows), marks the row taken, and registers the duplicate with its own reactor; the owner finds the row marked taken at its next turn and drops its registration and fd without shutting the connection down. A started request task never moves; only a row between requests does. TLS rows move with their session (the sans-io `MsTls` is thread-free state).
- Mail: a new `MS_MAIL_TAKE` kind posted with `ms_isolate_post`, handled by the server's `hooks.mail` on the taker's thread.
- Resting: the watcher reads each isolate's `sleeping` flag (`ms_isolate_idle_enter`/`leave`, already atomic and read by `ms_isolate_wake_one`), so bit `i` is isolate `i`; no new state besides `seen` and `stirred`.
- OS layer additions this needs (`runtime/sys`): a socket duplicate (`dup` on Unix; `WSADuplicateSocket` with the own process id and `WSASocket` on Windows, as the Rust `sys::duplicate` does), a nanosecond timed wait for the watcher (`uv_cond_timedwait`, which the clock granularity limits on Windows exactly as the Rust watcher is limited), and a "request waiting" probe that works on Windows (`WSAPoll`), since `ms_sys_fd_readable_now` has none.
- Balance: every 10 ms the member with the fewest connections takes half the difference from the one with the most when it is at least 4.
- Portable: atomics, `ms_sys_thread_spawn`, a condition wait and isolate mail; no timer, `timerfd`, kqueue or IOCP specifics.
- Cancellation and shutdown: the watcher ends in `ms_sched_teardown` of the last thread; a taken connection obeys its new owner's cancellation like any other.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `runtime/core/watch.{c,h}` | the watcher, epoch, hooks | `runtime/tests/core_watch.c`: a spinning thread is reported held up, a resting one is not, the watcher sleeps when all rest |
| `runtime/core/park.c`, `isolate.c` | turn and stir marks | existing core tests plus the above |
| `runtime/net/idle.{c,h}`, `runtime/core/promise.c`, `serve.ms` | idle pool, tagged id routing, take protocol, hook | `runtime/tests/net_idle.c`; fixture `http-long-handler-does-not-hold-others` on all platforms |
| `crates/ms-rt/src/watch.rs`, `ms-std-net` `steal.rs` | deleted when the C server serves | fixtures unchanged |

## Alternatives

- Do nothing: the C server fails the fixture; the Rust steal stays and `ms-std-net` cannot be deleted.
- Migrate a parked task whose fd is ready: a started task never moves. Its frames may keep a thread-local address across a park, its region and promises are thread-bound (`a-pinned-stream-keeps-every-promise-on-its-thread.md`), and handlers on other threads cost +75% CPU in the recorded trial.
- Kernel timers per thread, a wake per request, one shared poller: measured and rejected on the wiki page (arm and disarm 5.2 µs, 14 µs a request, 0 to 20% loss).
- Drop the periodic look: a task that computes never signals, so "held up" is only visible on a clock.

## Stages

1. `watch.c` with its test, marks in the park loop, the OS-layer additions; the Rust watcher still runs: `make verify`, idle fixture. Needs no server.
2. The idle pool with drain and timeouts (no stealing yet, the fixture still fails): `make verify`, idle fixture, `bench/perf/http-tail` against the baseline. Then the take protocol, hook and mail kind, behind the fixture; measure `bench/perf/http-tail` fast and slow mix against the latest dated baseline: CPU within the recorded 253 to 277 ticks, slow p50 0.62 to 0.64 ms.
3. Delete `watch.rs` and `steal.rs` with the Rust server.
