[Wiki](../index.md) › [Runtime](index.md)

# An inline blocking call starves posts from other threads

Verified (2026-11-12, Linux x86-64 VM): running a blocking file read on the scheduler thread because no other task is runnable (`pool::alone`, `msrt_task_others_stalled`) blocks everything posted to that thread meanwhile. With 20 ms per read, a promise completed on another thread woke its waiter 111 to 135 ms late. The pool hop exists to park the task so the thread stays free; the cost is about 40 ms more on a cold 2,000-file `pargroup` and about 4,700 `futex` calls warm.
Decision (owner): file reads keep the pool; #3638 (a joining task counts as stalled) was reverted. Do not widen `others_stalled` again. A faster path has to work on Linux, macOS and Windows alike; a Linux-only `openat2(RESOLVE_CACHED)` plus `preadv2(RWF_NOWAIT)` cache probe (closed PR #3656) and an `io_uring` spike (no better than the pool hop cold) were tried and not adopted.
Evidence: [`bench/perf/engineering/README.md`](../../bench/perf/engineering/README.md).
