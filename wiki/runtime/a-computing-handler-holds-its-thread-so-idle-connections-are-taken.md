[Wiki](../index.md) › [Runtime](index.md)

# A computing handler holds its thread, so other threads take its waiting connections

Verified: a task is never interrupted and a started task never moves, so a handler that computes stops its thread's reactor and every request on that thread's other connections waits (p99 rose to the handler time). The fix moves connections, not tasks: a connection between requests has little state, so each server lists those in a locked list (the socket, and for TLS the rustls session and for HTTP/2 the stream table, which the owner parks in the entry; the taker continues a TLS session on a duplicate of the socket, which needs no lock afterwards; only HTTP/2 with no open stream is listed), the watcher thread (`ms_rt::watch`) finds a thread that has not turned its reactor for a tick, and a resting thread of the same `serve` call duplicates the handle and serves it.

Rejected, do not retry: running handlers on other threads from the stdlib (+75% CPU, slower p50, lower throughput), one poller shared by all threads (connection state and tasks are thread-bound; no Windows equivalent), and firing a running task's time limit from the watcher (every cancellation point that matters already enters the scheduler, which fires it; Chinmay, 2026-11-15: leave pure loops alone, as Go does).

Rejected, do not retry: replacing the watcher's periodic look with a kernel timer per scheduler thread (PR 4238, 2026-11-16; Chinmay kept the periodic look). It worked and removed the watcher thread and its idle wakeups, but cost more than it saved on the hot path. Measured on the 4 vCPU shared VM against `main` and PR 4227's watcher, alternated runs:

| Design | Result | Why it lost |
| --- | --- | --- |
| A wake per request (the owner announces every handler start; or a rescuer thread fed by kernel readiness) | one wake and about 14 µs of CPU per request; 20% of closed-loop throughput | pays on every request to help the rare stuck one |
| One shared one-shot poller that every thread waits on | 0 to 20% throughput loss in an epoll microbenchmark | contention on the one set; connection state is thread-bound anyway |
| A nested exclusive wake (`EPOLLEXCLUSIVE` on an epoll descriptor) | `EINVAL`: the kernel refuses it | not available |
| A kernel timer per thread, armed on leaving rest and disarmed on resting, T = 250 µs | slow mix CPU 8.8 to 9.1 s vs 9.4 to 9.8 s, p99 equal; fast mix CPU 2.99 to 3.02 s vs 2.67 to 2.89 s (+8 to 10%); closed loop 122k to 128k vs 133k to 140k req/s (3 to 7% lower); idle 91 µs CPU, 1 switch | an arm plus disarm is 5.2 µs here (a VM exit programming the hrtimer), paid per rest cycle (1.8 per request): the whole fast-mix and closed-loop cost, with no cheaper form that keeps the guarantee (dropping the disarm lets a stale fire wake a peer on most rests; skipping the arm misses the first long handler) |

Timer length, one alternated sweep: 100 µs costs more CPU (fast 3.3 to 3.5 s, slow 10.0 to 10.3 s) because it fires on merely busy threads; 1 ms leaves a ready request waiting (slow p50 0.74 to 0.83 ms, p99 up to 5.7 ms); 250 µs sat near both floors. A "turn counter unchanged" test alone is wrong (the event that reports a request also wakes its owner); "has not rested since arming" is the test. Platform forms that worked: `timerfd` (Linux), a `libc` kqueue timer with `NOTE_NSECONDS | NOTE_CRITICAL` (macOS; `rustix` 1.1.5 encodes a sub-millisecond timer as zero), a high-resolution waitable timer plus thread-pool wait (Windows; one mio `Waker` per `Poll`, so timers share the poll's waker). Full record: [proposal](../../proposals/event-driven-waits.md).

Found while doing it, true of the watcher design too: a connection timeout started by a task other than the reactor (the accept loop adopting a connection, a finished request) while the reactor is parked with no sweep scheduled was not seen until something else woke the reactor; Windows' 50 ms park cap hid it. `Reactor::start_timeout` kicks the reactor in that case.

A watcher judges "held up" from a thread that was awake for a whole tick (`watch::stirred`); a thread that only just woke also has an old turn, and counting it kept the watcher ticking fast forever (+40% CPU at steady load).

Apply when: changing the HTTP reactor loop, connection ownership, or the scheduler's idle states.
Evidence: [steal.rs](../../crates/ms-std-net/src/http/server/steal.rs), [watch.rs](../../crates/ms-rt/src/watch.rs), [proposal](../../proposals/http-connection-stealing.md), [results](../../bench/perf/http-tail/README.md).
Verify: fixture `http-long-handler-does-not-hold-others`; `bench/perf/http-tail` slow mix p99 and fixed-load CPU against the dated baseline.
