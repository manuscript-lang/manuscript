[Wiki](../index.md) › [Runtime](index.md)

# A computing handler holds its thread, so other threads take its waiting connections

Verified: a task is never interrupted and a started task never moves, so a handler that computes stops its thread's reactor and every request on that thread's other connections waits (p99 rose to the handler time). The fix moves connections, not tasks: a connection between requests has little state, so each server lists those in a locked list (the socket, and for TLS the rustls session and for HTTP/2 the stream table, which the owner parks in the entry; the taker continues a TLS session on a duplicate of the socket, which needs no lock afterwards; only HTTP/2 with no open stream is listed), and a resting thread of the same `serve` call duplicates the handle and serves it when a thread stays out of rest too long.

Rejected, do not retry: running handlers on other threads from the stdlib (+75% CPU, slower p50, lower throughput), one poller shared by all threads (connection state and tasks are thread-bound; no Windows equivalent), a periodic watcher thread (100 µs to 2 ms looks, a 10 ms balance pass; Chinmay, 2026-11-16: no timed looks, they cost CPU and make the runtime fragile), and firing a running task's time limit from a watcher (every cancellation point that matters already enters the scheduler, which fires it; Chinmay, 2026-11-15: leave pure loops alone, as Go does).

No looks, no helper thread (Chinmay, 2026-11-16): every thread owns a kernel timer (timerfd, kqueue timer, Windows thread-pool timer) that its peers' pollers wait on. A thread arms it when it leaves rest and disarms it when it rests, two system calls per wake-up and nobody woken. It fires only for a thread that stayed out of rest for `HELP_AFTER_NS` (250 µs, the one documented number: a deadline with a meaning, not a period). "Held up" is the reactor's turn count unchanged since arming and no rest in between; then the woken thread takes the ready connections and re-arms, so later arrivals in the same stall are found within the same bound. With every thread resting nothing is armed. Balance runs when a connection count changes, and a take counts connections away at once.

Measured and rejected on the way (see the event-driven proposal): a shared one-shot poller (0 to 20% throughput loss), `EPOLLEXCLUSIVE` on a nested epoll (EINVAL), registering owners' pollers in a rescuer (a wake per request, 20% of closed-loop throughput), and a smaller T (CPU grows as 1/T).

Apply when: changing the HTTP reactor loop, connection ownership, or the scheduler's idle states.
Evidence: [steal.rs](../../crates/ms-std-net/src/http/server/steal.rs), [proposal](../../proposals/http-connection-stealing.md), [event-driven proposal](../../proposals/event-driven-waits.md), [results](../../bench/perf/http-tail/README.md).
Verify: fixture `http-long-handler-does-not-hold-others`; `bench/perf/http-tail` slow mix p99 and fixed-load CPU against the dated baseline.
