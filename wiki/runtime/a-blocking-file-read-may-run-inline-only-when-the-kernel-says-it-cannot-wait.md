[Wiki](../index.md) › [Runtime](index.md)

# A blocking file read may run inline only when the kernel says it cannot wait

Verified (2026-11-12, Linux x86-64 VM, ext4): running a read inline because "no other task could run" (`pool::alone`, `msrt_task_others_stalled`, widened to joiners in #3638) starves anything another thread posts to that thread during the read. With 20 ms per read, a promise completed on another thread woke its waiter 111 to 135 ms late, before and after #3638. The pool hop is what parks the task so the worker stays free for the disk's duration.
Rule: on Linux `read_file` tries `openat2(RESOLVE_CACHED)` and `preadv2(RWF_NOWAIT)` first. A hit is read on the thread. `EAGAIN` (cold) parks on the pool unless it is the only task. Other results (old kernel, file system without `RWF_NOWAIT`, directory) fall back to the `alone()` rule. macOS and Windows have no equivalent and keep that rule.
Trade-off: cold-cache `pargroup` is slower (83 to 130 ms) because each cold file costs a failed attempt plus a pool hop; warm is 36 to 25 ms.
Evidence: [`bench/perf/engineering/README.md`](../../bench/perf/engineering/README.md).
