[Wiki](../index.md) › [Runtime](index.md)

# The stealing watcher looks on a clock, by decision

Decision (Chinmay, 2026-11-16): the watcher thread (`src/runtime/core/watch.c`) keeps a periodic look; PR 4238, which replaced it with kernel timers, was closed unmerged. A second instruction the same day: keep the previous latencies, so a single fixed interval is out. This is the one deliberate periodic wait left in the runtime. It is not a poll for something that could signal: a task that computes never signals that it is stuck, so "a thread was held up" can only be seen by looking at how long it has gone without turning its reactor.

## Why kernel timers lost

A timer per scheduler thread, armed on leaving rest and disarmed on resting, removes the watcher thread and its idle wakeups. It worked (same slow-mix tail), but an arm plus disarm costs 5.2 µs on this VM (programming a one-shot timer is a VM exit) and a thread rests 1.8 times per request, so it cost what it saved:

| Measure (4 vCPU shared VM, alternated runs) | Watcher | Kernel timers, T = 250 µs |
| --- | --- | --- |
| Fast mix 4000 req/s, CPU for 40k requests | 2.67 to 2.85 s | 2.99 to 3.02 s (+8 to 10%) |
| Closed loop, 64 connections | 133k to 140k req/s | 122k to 128k req/s (3 to 7% lower) |
| Slow mix CPU, p50, p99 | 9.5 to 9.6 s, 0.61 to 0.63 ms, 2.4 to 2.9 ms | 8.8 to 9.1 s, 0.65 ms, 2.7 to 3.0 ms |
| Idle, 4 threads, 6 keep-alive connections, 1 s | about 22 context switches | 91 µs CPU, 1 switch |

No cheaper form keeps the guarantee: dropping the disarm lets a stale fire wake a peer on most rests, and skipping the arm misses the first long handler after a run of short ones. A wake per request (14 µs, 20% of throughput) and a shared poller (0 to 20% loss) lost earlier.

## What the watcher costs now

It looks every 2 ms while any thread is busy, every 100 µs for 0.1 s after a hook reports a thread held up for 1 ms, and sleeps after 20 looks with every thread at rest (a rest wakes it with one system call). Idle: fixture `http-idle-server-stays-asleep` requires under 40 context switches and under 100 ms of CPU a second (Windows counts CPU in 15.6 ms ticks); about 22 switches on Linux, none from a thread waking on a clock once it sleeps. Busy: fast mix 253 to 277 ticks and slow-mix p50 0.62 to 0.64 ms, p90 1.18 to 1.20 ms, against the fixed-interval alternatives in the stealing page (100 µs: +40% CPU; 1 ms: p50 +0.07 ms, p90 +0.15 ms).

## What would reopen it

A form with the two-mode latencies and no periodic look: for example a deadline armed by the event that makes a thread stuck (a handler start), which needs a cheap start announcement, since the measured costs above are all per request. Measure it with `bench/perf/http-tail` (`sweep.sh`, fast and slow mixes, closed loop) and the idle fixture against the dated results before proposing it, and expect Chinmay's call.

Apply when: touching `src/runtime/core/watch.c`, the steal hooks or the scheduler's rest states.
Evidence: [stealing page](a-computing-handler-holds-its-thread-so-idle-connections-are-taken.md), [proposal](../../proposals/event-driven-waits.md), [results](../../../bench/perf/http-tail/README.md), `src/runtime/core/watch.c`.
Verify: fixture `http-idle-server-stays-asleep`; `bench/perf/http-tail` against the latest dated baseline.
