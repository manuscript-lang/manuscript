# Promise fan-out and fork trees

`main.ms` has two modes: `fan N K` waits for K promises that each run `fib(N)`; `tree N CUTOFF` computes `fib(N)` with one promise per call at or above CUTOFF (a fork at every level, the shape parallel code takes when grain size is not tuned). The lower the cutoff, the finer the grain.

```sh
MS_THREADS=4 ms run bench/perf/promise-tree/main.ms -- tree 36 5
```

Serial `fib(36)` is 55 ms. Promises: cutoff 25 = 376, 15 = 46k, 10 = 514k, 5 = 5.7M.

## 2026-11-07 (x86-64 Linux sandbox, 4 cores, release `ms`)

Queue a promise on its creator's thread; a waiter runs a promise nobody took inline (guarded, so a fault still ends only that promise); another thread takes only starts older than 2 ms, oldest first. Before: every promise was placed on a thread and ran as a task.

| `tree 36` cutoff | before, 1 thread | after, 1 thread | before, 4 threads | after, 4 threads |
| --- | --- | --- | --- | --- |
| 25 (376) | 77 ms | 66 ms | 20 ms | 24 ms |
| 15 (46k) | 192 ms | 62 ms | 125 ms | 27 ms |
| 10 (514k) | 1951 ms | 162 ms | 1342 ms | 59 ms |
| 5 (5.7M) | 22198 ms | 1244 ms | 16408 ms | 470 ms |

Cost per promise at one thread: about 3.9 us before, 0.2 us after. Heavy fan-out is unchanged: `fan 38 8` takes 1565 / 730 / 346 ms before and 1366 / 704 / 388 ms after (4 threads measured with the 2 ms beat) on 1 / 2 / 4 threads. `mailbox` (100,000 short promises, window 64): 1,900 to 2,200 ns before, 418 ns after.

Not changed: a wait with a timeout or cancellation still runs the promise as a task, and `owned_promise` and I/O promises start where they were created.
