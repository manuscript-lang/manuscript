[Wiki](../index.md) › [Runtime](index.md)

# A computing handler holds its thread, so other threads take its waiting connections

Verified: a task is never interrupted and a started task never moves, so a handler that computes stops its thread's reactor and every request on that thread's other connections waits (p99 rose to the handler time). The fix moves connections, not tasks: a connection between requests has little state, so each server lists those in a locked list (the socket, and for TLS the TLS session and for HTTP/2 the stream table, which the owner parks in the entry; the taker continues a TLS session on a duplicate of the socket, which needs no lock afterwards; only HTTP/2 with no open stream is listed), the watcher thread (`src/runtime/core/watch.c`) finds a thread that has not turned its reactor for a tick, and a resting thread of the same `serve` call duplicates the handle and serves it.

Rejected, do not retry: running handlers on other threads from the stdlib (+75% CPU, slower p50, lower throughput), one poller shared by all threads (connection state and tasks are thread-bound; no Windows equivalent), and firing a running task's time limit from the watcher (every cancellation point that matters already enters the scheduler, which fires it; Chinmay, 2026-11-15: leave pure loops alone, as Go does).

Rejected, do not retry: replacing the watcher's periodic look with a kernel timer per scheduler thread (PR 4238, 2026-11-16; Chinmay kept the periodic look). It worked and removed the watcher thread and its idle wakeups, but cost more than it saved on the hot path. Measured on the 4 vCPU shared VM against `main` and PR 4227's watcher, alternated runs:

| Design | Result | Why it lost |
| --- | --- | --- |
| A wake per request (the owner announces every handler start; or a rescuer thread fed by kernel readiness) | one wake and about 14 µs of CPU per request; 20% of closed-loop throughput | pays on every request to help the rare stuck one |
| One shared one-shot poller that every thread waits on | 0 to 20% throughput loss in an epoll microbenchmark | contention on the one set; connection state is thread-bound anyway |
| A nested exclusive wake (`EPOLLEXCLUSIVE` on an epoll descriptor) | `EINVAL`: the kernel refuses it | not available |
| A kernel timer per thread, armed on leaving rest and disarmed on resting, T = 250 µs | slow mix CPU 8.8 to 9.1 s vs 9.4 to 9.8 s, p99 equal; fast mix CPU 2.99 to 3.02 s vs 2.67 to 2.89 s (+8 to 10%); closed loop 122k to 128k vs 133k to 140k req/s (3 to 7% lower); idle 91 µs CPU, 1 switch | an arm plus disarm is 5.2 µs here (a VM exit programming the hrtimer), paid per rest cycle (1.8 per request): the whole fast-mix and closed-loop cost, with no cheaper form that keeps the guarantee (dropping the disarm lets a stale fire wake a peer on most rests; skipping the arm misses the first long handler) |

Timer length, one alternated sweep: 100 µs costs more CPU (fast 3.3 to 3.5 s, slow 10.0 to 10.3 s) because it fires on merely busy threads; 1 ms leaves a ready request waiting (slow p50 0.74 to 0.83 ms, p99 up to 5.7 ms); 250 µs sat near both floors. A "turn counter unchanged" test alone is wrong (the event that reports a request also wakes its owner); "has not rested since arming" is the test. Platform forms that worked: `timerfd` (Linux), a `libc` kqueue timer with `NOTE_NSECONDS | NOTE_CRITICAL` (macOS; `rustix` 1.1.5 encodes a sub-millisecond timer as zero), a high-resolution waitable timer plus thread-pool wait (Windows; one mio `Waker` per `Poll`, so timers share the poll's waker). Full record: [proposal](../../proposals/event-driven-waits.md).

Found while doing it, true of the watcher design too: a connection timeout started by a task other than the reactor (the accept loop adopting a connection, a finished request) while the reactor is parked was not seen until something else woke it, so the deadline was late and an idle connection was not listed for stealing (the `a_listed_connection_*` tests stalled 10 to 30 s on one core). Waking the reactor on the first such timeout fixed it but cost +36% CPU at 4000 req/s on four threads with a 30 s timeout (254 to 344 ticks; no timeout, or one thread, +1 to 2%): an extra reactor pass per request. `settle_pending`, which the request task and the accept loop call before they end, reads the clock and resolves the timeouts on the same thread, and wakes the reactor only when the earliest sweep changed (250 ticks, like main). Do not wake the reactor per started timeout.

The watcher keeps two modes (a look every 2 ms, every 100 µs for 0.1 s after a thread was held up 1 ms) and sleeps after 20 looks with every thread resting. Chinmay, 2026-11-16: keep the previous latencies, so one fixed interval is rejected. Sweep, three alternated rounds of 12 s, CPU in 10 ms ticks per run:

| Interval | Fast mix CPU | TLS CPU | Slow mix p50 / p90 / p99 | Closed loop |
| --- | --- | --- | --- | --- |
| Two modes (kept) | 253 to 277 | 299 to 313 | 0.62 to 0.64 / 1.18 to 1.20 / 3.4 to 3.5 ms | 131k to 143k |
| 100 µs | 373 to 385 | 407 to 445 | 0.61 / 1.18 / 1.7 to 3.6 ms | 130k to 140k |
| 250 µs | 304 to 327 | 363 to 375 | 0.65 to 0.69 / 1.2 to 1.35 / 2.2 to 6.2 ms | 135k to 143k |
| 500 µs | 280 to 292 | 313 to 326 | 0.65 to 0.67 / 1.23 to 1.25 / 2.5 to 3.3 ms | not run |
| 1 ms (rejected: p50 and p90) | 260 to 271 | 300 to 327 | 0.69 to 0.72 / 1.34 to 1.47 / 3.4 to 3.7 ms | 145k to 153k |

CPU scales with the look count; 1 ms costs what the two modes cost, but its slow-mix p50 is about 0.07 ms and p90 about 0.15 ms above the two modes (a ready request waits up to a look longer behind a held-up thread), with p99 and p99.9 the same, and the fixed 100 µs and 250 µs forms cost 20 to 45% more CPU. A thread awake for a whole interval is the test for "held up" (`watch::stirred`): a thread that only just woke also has an old turn. Each wake of a sleeping watcher is a system call on the thread that leaves its rest, which is why it sleeps only after a run of quiet looks (20 looks, 40 ms; 100 looks left a 200 ms burst of 100 wakes after every sleep that ended a rest).

Apply when: changing the HTTP reactor loop, connection ownership, or the scheduler's idle states.
Evidence: `src/runtime/std/http_serve_steal.c`, `src/runtime/core/watch.c`, [proposal](../../proposals/http-connection-stealing.md), [results](../../../bench/perf/http-tail/README.md).
Verify: fixture `http-long-handler-does-not-hold-others`; `bench/perf/http-tail` slow mix p99 and fixed-load CPU against the dated baseline.
