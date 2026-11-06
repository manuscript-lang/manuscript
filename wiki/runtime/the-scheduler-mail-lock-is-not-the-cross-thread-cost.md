[Wiki](../index.md) › [Runtime](index.md)

# The scheduler mail lock is not the cross-thread cost

Verified (2026-11-06, x86-64 Linux sandbox, 4 cores): a promise costs about 3.5 µs and 5 acquisitions of a slot's mail lock; 8% of acquisitions were contended. A lock-free event inbox (atomic-swap Treiber stack, passing a producer stress test) made no measurable difference over five alternating runs, so it was dropped. Removing runtime locks one by one is not a speed lever for promises; look at the wake path (`sched::wake`, `isolate::kick`, the poller) first.
Apply when: proposing to replace a `Mutex` in `sched.rs`, `isolate.rs` or the pool with an atomic structure for speed.
Evidence: [`bench/perf/mailbox/README.md`](../../bench/perf/mailbox/README.md).
Verify: `ms run bench/perf/mailbox/main.ms -- 100000 5`; count `lock` calls in `sched.rs` with a temporary counter.
