[Wiki](../index.md) › [Runtime](index.md)

# Timed waits are a deadline with a meaning or armed by an event, never a poll

Rule (Chinmay, 2026-11-16: "i dont like all these random sleeps and waits, they make the software fragile"): a wait is a deadline that means something (user timeout, grace period, retry policy, protocol delay) or one deadline armed by an event. A wait that wakes on a period to see whether something changed is replaced by the event it waits on. The Rust build counted `sleep(`, `park_timeout(` and similar per file against an allow list in `make repo-check`; that tripwire was not ported to the C build, so review new waits by reading.

How to replace a polling wait (patterns that held up):
- Block on the descriptor, token or channel until ready or the deadline, never on a slice. A watcher or stream that must end on `close` parks on a wakeup token that `close` signals (store the id, re-check `closed`, then park).
- Child exit parks on a pidfd (Linux), an `EVFILT_PROC` kqueue (macOS) or the process handle (Windows). The terminal's input wait has no slice: it blocks on a pool thread until input, a resize or a close, and a stop request ends a blocking pipe read (`CancelIoEx` on Windows, repeated until a started job is done, since it does nothing before the read is issued).
- Where a test sleep stands for "later than the operation", order the events instead; a condition wait on the state replaces a 1 to 500 ms sleep.
- Rejected: replacing the HTTP watcher's periodic look with kernel timers (PR 4238, see [the stealing page](a-computing-handler-holds-its-thread-so-idle-connections-are-taken.md)); it costs the hot path more than it saves.
- Kept, with a reason: `FileHandle.lock` retries every 5 ms with the caller's deadline (`flock` and `LockFileEx` have no timed wait, and a blocking lock on a pool thread cannot be cancelled, so it would take the lock after the caller gave up); `ms --watch` polls (decided 2026-11-16, Chinmay); the scheduler beats in `src/runtime/core/worker.h` (one deadline armed by an event); user timeouts in dns, tls and the HTTP client; the HTTP server's earliest-deadline sweep; the terminal's 40 ms lone-Escape wait (the terminal sends no end marker); resilience retry and throttle; SSE `retry_ms`; the language server's debounce and restart windows.

A native that waits in a loop must honor the task's read limit before each park. `ReadStream.next(timeout:)` sets a limit on the task, and every park past it returns at once as a timeout; a loop that only retries then spins a core and never ends (the native watcher, the polling watcher, the signal stream and the terminal event stream did this). The wait returns the timeout status once the limit has passed. Fixture: `watch-and-signal-reads-time-out.ms`.

Apply when: adding a wait, a sleep in a test, or a retry loop.
Evidence: [proposal](../../proposals/event-driven-waits.md), `src/runtime/core/park.c`, `src/runtime/io/`.
Verify: the new wait wakes on its event with no timer running, and `ms test` with the fixture above passes.
