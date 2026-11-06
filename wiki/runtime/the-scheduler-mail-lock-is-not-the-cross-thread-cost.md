[Wiki](../index.md) › [Runtime](index.md)

# The scheduler mail lock is not the cross-thread cost

Verified (2026-11-06, x86-64 Linux sandbox, 4 cores): a promise costs about 3.5 µs and 5 acquisitions of a slot's mail lock; 8% of acquisitions were contended. A lock-free event inbox (atomic-swap Treiber stack, passing a producer stress test) made no measurable difference over five alternating runs, so it was dropped. Removing runtime locks one by one is not a speed lever for promises; the wake path is the better target (`sched::wake`, `isolate::kick`: 1.4 eventfd writes and three mutexes per promise, 90% of them for a thread that is not sleeping), but a plain "skip the kick unless the target is about to block" gate was slower (5.5 against 3.4 µs per promise) because `kick` also maintains the isolate idle count and some blocked threads rely on it.
Apply when: proposing to replace a `Mutex` in `sched.rs`, `isolate.rs` or the pool with an atomic structure for speed.
Evidence: [`bench/perf/mailbox/README.md`](../../bench/perf/mailbox/README.md).
Verify: `ms run bench/perf/mailbox/main.ms -- 100000 5`; count `lock` calls in `sched.rs` with a temporary counter.
