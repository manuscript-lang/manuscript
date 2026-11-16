[Wiki](../index.md) › [Runtime](index.md)

# Timed waits are a deadline with a meaning or armed by an event, never a poll

Rule (Chinmay, 2026-11-16: "i dont like all these random sleeps and waits, they make the software fragile"): a wait is a deadline that means something (user timeout, grace period, retry policy, protocol delay) or one deadline armed by an event. A wait that wakes on a period to see whether something changed is replaced by the event it waits on. `make repo-check` enforces it: `crates/ms-repo-check/src/timed_waits.rs` counts `sleep(`, `park_timeout(`, `recv_timeout(` and `wait_timeout` per file against `timed-waits-allowed.txt` (path, count, reason); a count above the list fails, and a count below it fails too, so the list only shrinks. It is a textual tripwire, not a parser: it also counts `fn sleep(`, `try_task_sleep(` and `sleep(` inside strings and test modules, cuts a line at `//` even inside a string, and does not see other forms (`poll_one(.., Some(slice))`, `wait_ready(.., ms)`, `libc::poll` timeouts, `Gate::park(ns)`), so a new polling wait can pass it; review for those by reading. A new wait needs a reason in the list; a converted one lowers its count.

Done (2026-11-16): the unit-test thread wait in `ms-std-net/src/wait.rs` blocks on the descriptor until ready or the deadline (no 50 ms slice; `sys::poll_one` takes an optional timeout on Unix and Windows); the file watcher's Linux inotify wait and the polling watcher's sleep wake on `close` through `ms_rt::glue::Wakeup` (a token a task parks on and any thread can signal; store the id, re-check `closed`, then park) instead of re-checking every 50 ms; the guard; the accept loop (2026-11-16, the runtime retries per-connection errors at once; any other error backs off 5 ms doubling to 1 s); the h2 reset-stream and pool tests wait on events instead of sleeping. The kqueue (macOS) watcher parks on the kqueue descriptor and `close` triggers an `EVFILT_USER` event; the `ReadDirectoryChangesW` (Windows) watcher parks on the request's manual-reset event through `glue::object`, `close` sets the same event, and the event is reset before each look so no signal is lost (both verified by CI only).

Rejected: replacing the HTTP watcher's periodic look with kernel timers (PR 4238, see [the stealing page](a-computing-handler-holds-its-thread-so-idle-connections-are-taken.md)); it was measured and costs the hot path more than it saves.

## Still polling, with the event to use (do these next, in this order: flaky test waits, Linux product polls, platform items)

| Where | Wait | What replaces it |
| --- | --- | --- |
| Test waits: `ms-std-net` server, client and h2 tests (`wait::sleep(2 ms)` loops, 10 to 500 ms sleeps, e.g. `a_reset_stream_cancels_its_running_handler`), `ms-rt` `pool.rs` and `task/tests.rs`, `sched.rs` `warm` (1 ms loop), `ms-std-fs` watch tests | 1 to 500 ms | Condition wait on the state (channel, condvar, token). Where a sleep stands for "later than the operation", order the events instead. Allowed counts are in `timed-waits-allowed.txt` with the reason `test` |
| `ms-std-terminal/src/raw.rs` `SLICE_NS` (Unix) | 50 ms | Wait for input with no bound; `close` wakes it (eventfd or pipe in the same wait) |
| stdlib `os/fs.ms` `FileHandle.lock` | retry every 5 ms with a timeout | Kernel gap (`flock` has no timed wait). Either keep and document, or a blocking `flock` on a pool thread (a thread blocked for the timeout) |
| `ms-std-net/src/sys/windows.rs` `PARK_NS` | 50 ms cap on the reactor park | Park with the caller's deadline and no cap (it was done and proven on the PR 4238 branch, with the `start_timeout` kick; needs Windows CI) |
| `ms-std-process/src/signals_windows.rs` `SLICE_MS` | 50 ms | The signal handler sets an event the task waits on (Windows CI) |
| `ms-std-fs/src/stream.rs` `POLL_SLICE_MS` and `sys/windows.rs` `pause_2ms`; `ms-std-terminal/src/sys_windows.rs` `wait_readable` (10 ms) | 50, 2 and 10 ms | Kernel gap for pipes and the console: a blocking-pool wait on the handle plus a cancel event (`WaitForMultipleObjects`), or overlapped reads (Windows CI) |
| `ms-std-process/src/command.rs` `POLL_MS` | 2 ms on macOS and Windows (Linux parks on a pidfd) | macOS `EVFILT_PROC` in the poller; Windows a wait on the process handle through the pool (macOS and Windows CI) |
| `ms-cli` file watching (`WATCH_INTERVAL` 10 ms in `engine/tooling.rs`, `watch.rs`), `recv_timeout(100 ms)` loops draining child output (`engine/run.rs`, `testing.rs`), `process.rs` nap, `ms-conform` `exec.rs` 5 ms child poll | 5 to 100 ms | A channel close or a child exit; tooling, so its own PR |

## Kept, named

`SPIN_NS` 20 µs (bounded spin before a sleep), `SPIN_BELOW_NS` 1 ms (epoll rounds timers to a millisecond, so a shorter one spins and ends at the timer), `BEAT_NS`, `OWN_HOLD_NS`, `STEAL_*_NS` (one deadline armed by an event), `CLEANUP_GRACE_SECS` 30 s, `CANCEL_FLUSH` 200 ms, the HTTP server's `next_sweep` (earliest deadline), user timeouts in dns, tls, exchange and client, `WAIT_DELAY_NS` 1 s (`exec.Cmd.WaitDelay`), the terminal's 40 ms lone-Escape wait (the terminal sends no end marker), resilience retry and throttle, SSE `retry_ms`, `ms-lsp` debounce and restart windows, and the watcher's own look interval (see the stealing page).

Apply when: adding a wait, a sleep in a test, or a retry loop.
Evidence: [timed_waits.rs](../../crates/ms-repo-check/src/timed_waits.rs), [allow list](../../crates/ms-repo-check/timed-waits-allowed.txt), [wait.rs](../../crates/ms-std-net/src/wait.rs), [watch.rs](../../crates/ms-std-fs/src/watch.rs), [proposal](../../proposals/event-driven-waits.md).
