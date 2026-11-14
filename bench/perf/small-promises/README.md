# Many small promises across threads

`main.ms` starts 100,000 promises that each do about 1 us of work and waits for all of them. It should not get slower as threads are added (issue #3885).

```sh
ms build bench/perf/small-promises/main.ms -o small && MS_THREADS=4 ./small
```

## 2026-11-14 (x86-64 Linux sandbox, 4 cores, release `ms`, revision 99afe5ed plus this change)

Median of 11 runs of the built program. Before: every promise that ran on another thread made its creator spawn a task (a fresh stack, one `madvise` each) just to drop the closure; 100k were queued at once. After: the creator drains those ends through at most four reusable tasks.

| threads | before | after |
| --- | --- | --- |
| 1 | 105 ms | 117 ms (noise; the 1-thread path is unchanged) |
| 2 | 426 ms | 129 ms |
| 4 | 493 ms | 185 ms |

`strace -c -f` at 4 threads: 100,221 `madvise` calls before.
