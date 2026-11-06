[Wiki](../index.md) › [Runtime](index.md)

# Cross-thread promise cost is the sleep and wake, not the mail lock

Verified (2026-11-06, x86-64 Linux sandbox, 4 cores): a promise cost about 3.5 µs and 5 acquisitions of a slot's mail lock, 8% of them contended. A lock-free event inbox (atomic-swap Treiber stack) made no difference. The cost was the wake path: `isolate::kick` took three mutexes, two global (`REGISTRY`, `IDLE`), and wrote an eventfd for 90% of wake-ups whose target was not sleeping. Making the registry and the idle count lock-free and writing the eventfd only when the target is about to block (`isolate::set_sleeping`, re-checked after setting) made it slower (5.4 µs), because threads then slept and woke through `epoll_wait` for every promise; adding a 20 µs spin before sleeping (`task::spin_for_work`, skipped with one scheduler thread) reached 1.9 µs. So the order matters: remove the lock only together with something that keeps a just-idle thread awake.
Apply when: touching `isolate.rs` idle accounting, `sched::wake`, or `reactor_wait`; a poster publishes its work, then unparks, then wakes if the target is flagged sleeping; a sleeper flags, then looks for work once more.
Evidence: [`bench/perf/mailbox/README.md`](../../bench/perf/mailbox/README.md).
Verify: `ms run bench/perf/mailbox/main.ms -- 100000 5`; `cargo test -p ms-rt remote_posts_never_miss_a_sleeping_scheduler`.
