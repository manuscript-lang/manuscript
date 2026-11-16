[Wiki](../index.md) › [Runtime](index.md)

# A computing handler holds its thread, so other threads take its waiting connections

Verified: a task is never interrupted and a started task never moves, so a handler that computes stops its thread's reactor and every request on that thread's other connections waits (p99 rose to the handler time). The fix moves connections, not tasks: a plain HTTP/1 connection between requests has no state but its socket, so each server lists those in a locked list, the watcher thread (`ms_rt::watch`) finds a thread that has not turned its reactor for a tick, and a resting thread of the same `serve` call duplicates the handle and serves it.

Rejected, do not retry: running handlers on other threads from the stdlib (+75% CPU, slower p50, lower throughput), one poller shared by all threads (connection state and tasks are thread-bound; no Windows equivalent), and firing a running task's time limit from the watcher (every cancellation point that matters already enters the scheduler, which fires it; Chinmay, 2026-11-15: leave pure loops alone, as Go does).

A watcher judges "held up" from a thread that was awake for a whole tick (`watch::stirred`); a thread that only just woke also has an old turn, and counting it kept the watcher ticking fast forever (+40% CPU at steady load).

Apply when: changing the HTTP reactor loop, connection ownership, or the scheduler's idle states.
Evidence: [steal.rs](../../crates/ms-std-net/src/http/server/steal.rs), [watch.rs](../../crates/ms-rt/src/watch.rs), [proposal](../../proposals/http-connection-stealing.md), [results](../../bench/perf/http-tail/README.md).
Verify: fixture `http-long-handler-does-not-hold-others`; `bench/perf/http-tail` slow mix p99 and fixed-load CPU against the dated baseline.
