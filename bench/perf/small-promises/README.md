# Many small promises across threads

`main.ms` starts 100,000 promises that each do about 1 us of work and waits for all of them. It should not get slower as threads are added (issue #3885).

```sh
ms build bench/perf/small-promises/main.ms -o small && MS_THREADS=4 ./small
```

## 2026-11-14 (x86-64 Linux sandbox, 4 cores, release `ms`, revision 99afe5ed plus this change)

Median of 11 runs of the built program. Before: every promise that ran on another thread made its creator spawn a task (a fresh stack, one `madvise` each) just to drop the closure; 100k were queued at once. After: the creator drains those ends through at most four reusable tasks, and events other threads post to a thread no longer share a lock and cache line with that thread's queue of unstarted promises (while the creator queued 100k starts, three other threads posting events made creation take 110 to 140 ms instead of 22 ms).

| threads | before | after |
| --- | --- | --- |
| 1 | 105 ms | 117 ms (noise; the 1-thread path is unchanged) |
| 2 | 426 ms | 116 ms |
| 4 | 493 ms | 132 ms |

`strace -c -f` at 4 threads: 100,221 `madvise` calls before.

Controls (`promise-tree`, `tree 36`, same machine, before / after): cutoff 10 on 1 / 4 threads 255 / 101 ms to 213 / 83 ms; cutoff 5 1813 / 728 ms to 1660 / 631 ms.

`wait_all` used to poll `done()`, which starts the next unstarted promise as a task (a stack, two context switches and three events each), then block. It now first runs the next promise on its own stack when nobody has taken it (`msrt_promise_run_unstarted`), the way `wait` does. Medians of 11, before / after this step: 1 thread 109 / 71 ms, 2 threads 104 / 105 ms, 4 threads 121 / 128 ms (noise).

Not fixed: with 2 or 4 threads the run is still no faster than 1 thread. A promise this small (about 0.3 us of work) costs a thief more to take (a task, three mail events) than the work itself, so stolen promises add cost instead of removing it. Callgrind at 1 thread: about 5,100 instructions of promise machinery per promise against 3,200 of work.

## 2026-11-14: a thread that steals tiny promises pauses

x86-64 Linux sandbox, 4 cores, release `ms`. A stolen promise that ends within 5 us of being taken (a steal costs a task and three events) makes its thief stop stealing for 50 us, doubling up to 2 ms while that repeats; a longer one resets the pause. Idle threads sleep for the pause instead of spinning on the creator's queue. 100k promises, `MS_THREADS=4`, 15 interleaved runs each, before / after: median 190 / 125 ms, user CPU 660 / 170 ms. 1 thread is unchanged (about 65 ms); 2 threads is still not faster than 1. Controls: `promise-tree tree 36 10` 1 / 4 threads 181 / 62 ms, `tree 36 5` 1487 / 533 ms (README above: 213 / 83 and 1660 / 631 ms before); the 16 CPU-bound chunks of `workers` are unchanged at 4 threads (about 270 ms).

Tried and dropped: a thief taking up to 64 starts per steal into its own queue (creation 70 to 30 ms, but the wait got slower, 95 to 130 ms); a thief taking the newest start instead of the oldest (no change).

## 2026-11-14, second step: a paused thief reads no other thread's queue

While paused, `steal_wait_ns` (polled in the idle spin) now returns the end of the pause without reading the other threads' `front_at`, the line the creator rewrites on every pop. 100k promises, `MS_THREADS=4`, 11 interleaved runs each, before / after: min 115 / 88 ms, median 146 / 125 ms (1 thread: 64 ms, 2 threads about 100 ms). Controls on 4 threads: primes chunks 232 to 218 ms best, `promise-tree tree 36 10` 49 ms, `tree 36 5` 432 ms. What is left is the creator running slower with several threads started (user CPU about equals wall time), not stealing.
