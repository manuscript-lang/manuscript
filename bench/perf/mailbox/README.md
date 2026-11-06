# Scheduler mailbox traffic

`main.ms` starts N short promise tasks from the main thread in rounds and waits for each, so every promise sends a start to a scheduler thread and an event back. It measures the cross-thread mail path (`sched.rs` `submit`, `post`, `take_events`, `next_pending`).

```sh
ms run bench/perf/mailbox/main.ms -- 100000 5
```

## 2026-11-06 (x86-64 Linux sandbox, 4 cores, release Cranelift `ms`)

Counting every acquisition of a slot's mail lock over 500,000 promises: 2.4 million acquisitions (about 5 per promise), of which 8% found the lock held (events: 1.4 million, 11.5% contended; pending starts: 1.0 million, 3.8%). Run time is about 3.5 µs per promise.

Replacing the event list with a lock-free multi-producer inbox (an atomic-swap Treiber stack, with a two-producer-stress test) changed nothing measurable: 3.4 to 3.8 µs per promise before, 3.5 to 4.3 after, five alternating runs, inside the run-to-run noise. The lock is not where a promise's time goes, so the change was not kept. The cost is the wake and context-switch path (`wake`, the poller kick), not the list lock.
