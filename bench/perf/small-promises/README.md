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
