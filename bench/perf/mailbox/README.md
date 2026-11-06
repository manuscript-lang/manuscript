# Scheduler mailbox traffic

`main.ms` starts N short promise tasks from the main thread in rounds and waits for each, so every promise sends a start to a scheduler thread and an event back. It measures the cross-thread mail path (`sched.rs` `submit`, `post`, `take_events`, `next_pending`).

```sh
ms run bench/perf/mailbox/main.ms -- 100000 5 [window]
```

The `window` (default 64) is how many promises are in flight at once. Keep it small: with every promise alive at once each needs a fresh task stack (a guard `madvise` per promise), which hides the mail cost.

## 2026-11-06 (x86-64 Linux sandbox, 4 cores, release Cranelift `ms`)

Counting every acquisition of a slot's mail lock over 500,000 promises: 2.4 million acquisitions (about 5 per promise), of which 8% found the lock held (events: 1.4 million, 11.5% contended; pending starts: 1.0 million, 3.8%). Run time is about 3.5 µs per promise.

Replacing the event list with a lock-free multi-producer inbox (an atomic-swap Treiber stack, with a two-producer-stress test) changed nothing measurable: 3.4 to 3.8 µs per promise before, 3.5 to 4.3 after, five alternating runs, inside the run-to-run noise. The lock is not where a promise's time goes, so the change was not kept. The cost is the wake and context-switch path (`wake`, the poller kick), not the list lock.

## Wake path (same day, window 64)

`strace -f -c` over 100,000 promises: 136,000 eventfd `write`s (1.4 per promise, from `sched::wake` to `isolate::kick`), 111,000 `futex` calls (1.1 per promise), and only 10,600 `epoll_wait`s, so about 90% of the wake-ups hit a thread that was not sleeping. `kick` also takes three locks per call (the global `REGISTRY` and `IDLE` mutexes and the target's `wake` mutex). Skipping the wake when the target had not announced it was about to block in `reactor_wait` made the run slower (5.5 µs against 3.4 µs per promise), so some blocked threads are woken only by that kick: a safe version must also cover the idle-count bookkeeping `kick` does under `IDLE`. Not kept; the next try needs a design that keeps the deadlock count correct, not a gate.
