# Parked tasks: memory and time per task

What a promise task costs while it is parked, and how spawning and cancelling scale. The program
starts N promise tasks that park on a timer (`sleep`), park after a 256-frame call chain (`deep`,
a handler that did real work before waiting), or park after a file read (`read`), then prints the
process's resident set, high-water mark and page tables before, with every task parked, and after
the scheduler's idle rounds hibernated them. The report reads `/proc/self/status`, so it is
Linux only; the tasks are portable.

```sh
ms run bench/perf/tasks/main.ms -- 1000000 sleep
```

## 2026-11-04: 512 KiB slots in 256 MiB regions, idle hibernation

Revision: the change that introduced this page, on `1e1b2d4a`. Machine: Intel Xeon 2.80 GHz,
4 vCPUs, 16 GB, Linux 6.18 (sandbox), release `ms` (LLVM). Resident and page-table figures are
`VmRSS` and `VmPTE` divided by N; "parked" is with every task waiting, "idle" after hibernation.

| Tasks | Mode | Parked RSS/task | Idle RSS/task | Page tables/task | Spawn | Cancel |
| --- | --- | --- | --- | --- | --- | --- |
| 100k | sleep | 5.0 KB | 3.8 KB | 1.0 KB | 0.5 s | 0.4 s |
| 100k | deep | 9.0 KB | 3.8 KB | 1.0 KB | 0.5 s | 0.4 s |
| 1M | sleep | 5.0 KB | 3.8 KB | 1.0 KB | 9.8 s | 7.2 s |
| 1M | deep | 9.0 KB | 3.8 KB | 1.0 KB | 3.7 s | 3.5 s |

A million hibernated tasks hold 3.76 GB resident plus 1.01 GB of page tables: 4.8 GB on an 8 GB
machine, with 1,024 mappings (one per 256 MiB region; the guards are `MADV_GUARD_INSTALL`
regions on this kernel and split nothing). Spawn and cancel stay near linear: 1M tasks in 3.7 to 9.8 s
and 3.5 to 7.2 s against 0.5 s and 0.4 s for 100k, most of it kernel time for page faults and
`madvise` (the cancel was quadratic before the promise table learned its task, #2539, and a 1M
run never finished).

What remains per hibernated task is the park depth, 2.9 KB of frames from `Promise.wait` down to
the scheduler's `switch_away`, kept on the heap with an exact-size `malloc`, plus about 0.9 KB of
records (task, promise slot, closure, timer). The stack high-water mark no longer matters once a
task has parked for two idle rounds: `deep` and `sleep` meet at 3.8 KB. Thinner frames on the
wait path are the next lever.

Before this change (256 MiB slots, `mprotect` guards, two mappings per task) the process hit
`vm.max_map_count` near 32k tasks (#2483), so there is no same-machine 1M baseline to compare
with; at 100k the old layout would not start.

## 2026-11-04: stack growth (`growth.ms`, release LLVM, x86-64 sandbox, 4 cores)

A task starts on one 512 KiB slot and grows by guarded segments. `growth.ms` times a loop of
20,000 calls of `depth(3400)`, each of which crosses the first slot's boundary and comes back,
against the same loop with `depth(3000)` (no crossing) and both on the main task (256 MiB, never
grows), then a 900,000-frame recursion.

| run | task 3000 × 20k | task 3400 × 20k | main 3000 × 20k | main 3400 × 20k | task 900k | main 900k |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 525 ms | 654 ms | 589 ms | 536 ms | 23 ms | 22 ms |
| 2 | 497 ms | 563 ms | 516 ms | 656 ms | | |
| 3 | 570 ms | 648 ms | 612 ms | 668 ms | | |

The loop that crosses the boundary on every call runs as fast as the same loop on the main task;
run-to-run noise (about 10%) is larger than any crossing cost, so one crossing is well under a
microsecond: the task keeps its second segment, and a crossing is a few stores, the segment's
bookkeeping and the stack switch. The 900k-frame recursion (about 125 MB of frames over 240
segments) costs the same in a task as on the main task.
