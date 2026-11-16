[Wiki](../index.md) › [Runtime](index.md)

# A computing handler holds its thread, so other threads take its waiting connections

Verified: a task is never interrupted and a started task never moves, so a handler that computes stops its thread's reactor and every request on that thread's other connections waits (p99 rose to the handler time). The fix moves connections, not tasks: a plain HTTP/1 connection between requests has no state but its socket, so each server lists those in a locked list, the rescuer thread (`steal.rs`) hears that a thread may hold an unread request and arms one deadline (100 µs), and if that thread's reactor has not turned by then a resting thread of the same `serve` call duplicates the handle and serves it.

Rejected, do not retry: running handlers on other threads from the stdlib (+75% CPU, slower p50, lower throughput), one poller shared by all threads (connection state and tasks are thread-bound; no Windows equivalent), a periodic watcher thread (100 µs to 2 ms looks, a 10 ms balance pass; Chinmay, 2026-11-16: no timed looks, they cost CPU and make the runtime fragile), and firing a running task's time limit from a watcher (every cancellation point that matters already enters the scheduler, which fires it; Chinmay, 2026-11-15: leave pure loops alone, as Go does).

Events, not looks: the kernel's readiness on a thread's poller (its epoll or kqueue descriptor registered in the rescuer's poll; on Windows the poller's helper thread wakes it) and a reactor's own batch of ready connections (`Beat::stranded`) are the two ways a stranded request is noticed. "Held up" is the reactor's turn count unchanged after the deadline while the thread does not rest. With no thread resting the rescuer waits for one to rest (`sched::watch_rests`), it does not look again. Balance runs when a connection count changes, and a take counts connections away at once so a second look sees the group even.

Apply when: changing the HTTP reactor loop, connection ownership, or the scheduler's idle states.
Evidence: [steal.rs](../../crates/ms-std-net/src/http/server/steal.rs), [proposal](../../proposals/http-connection-stealing.md), [event-driven proposal](../../proposals/event-driven-waits.md), [results](../../bench/perf/http-tail/README.md).
Verify: fixture `http-long-handler-does-not-hold-others`; `bench/perf/http-tail` slow mix p99 and fixed-load CPU against the dated baseline.
