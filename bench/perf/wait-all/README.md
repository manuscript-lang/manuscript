# Pending promise fan-in

`main.ms COUNT jitter|immediate [ordered]` creates COUNT promises, waits, and checks
both result count and input order. Jitter sleeps for `i % 5` milliseconds. Immediate
work and small counts are neighboring-case controls. `ordered` retains the old
list-order loop only as a performance control: it does **not** provide current
`wait_all`'s prompt failure reporting and is not an API replacement.

Build two revisions with the same compiler options, then alternate their binaries:

```sh
MS_BACKEND=cranelift ms build bench/perf/wait-all/main.ms --build-type Release -o wait-all
MS_THREADS=4 ./wait-all 40000 jitter
MS_THREADS=4 ./wait-all 16 jitter
MS_THREADS=4 ./wait-all 40000 immediate
MS_THREADS=4 ./wait-all 40000 jitter ordered
```

For runtime-only comparisons, build each revision with
`cargo build --release --locked -p ms-native --features entry`, preserve the resulting
`libms_native.a`, and set `MS_RT_LIB=/absolute/path/to/archive` for each `ms build`.
The compiler must embed current stdlib declarations, including #2915's `wait_all`.
Do not substitute a stale installed compiler. Run at least seven alternating pairs,
check every exit status, and compare medians on one machine, not across hosts.
`total_ns` includes spawn, wait and result validation; `spawn_ns` isolates spawn.

## 2026-11-07

Issue [#2932](https://github.com/manuscript-lang/manuscript/issues/2932). Before:
`f9da21fc6863493db80adfbe91ff89cf5c12e3f8` (main, including #2915). After: the same
source with only `promise.rs`'s readiness-rescan optimization. Both native archives
were freshly built in release mode from those sources, including the `entry`
feature. Both executables used the same compiler freshly built from that main
revision, current embedded stdlib, Cranelift Release, and explicit `MS_RT_LIB`
overrides. The compiler's embedded fallback runtime was not used.

Host: Linux x86-64 6.18.57, Intel Xeon Platinum 8370C at 2.8 GHz, shared sandbox,
Rust 1.99.1 (`58cf8f9c3`, 2026-10-13), `MS_THREADS=4`. Seven paired runs, alternating
before/after order. Every sample returned the correct input-ordered results and
checksum (799980000 for 40000). Raw nanosecond samples:
[`samples-2026-11-07.tsv`](samples-2026-11-07.tsv).

| Count / work | Before median | After median |
| --- | ---: | ---: |
| 16 / jitter | 4.81 ms | 4.71 ms |
| 1000 / jitter | 11.89 ms | 10.09 ms |
| 4000 / jitter | 44.50 ms | 18.70 ms |
| 16000 / jitter | 454.45 ms | 52.27 ms |
| 40000 / jitter | 3159.52 ms | 96.61 ms |
| 40000 / immediate | 283.77 ms | 265.22 ms |

The first seven-pair ordered control varied from 99.09 ms before to 132.81 ms
after. A separate 21-pair alternating control was 118.12 ms before / 107.75 ms
after. Some initial samples overlapped background test compilation, and this is a
shared host: these controls establish the approximate 0.1-second range, not a
precise small percentage change. The roughly 33x large-jitter improvement is much
larger than this noise.

A separate Rust-only probe allocated pending promise slots, then timed a zero-timeout
`wait_any`, excluding allocation and drop. Seven alternating release samples:

| Pending slots | Before median | After median |
| --- | ---: | ---: |
| 1000 | 2.568 ms | 0.038 ms |
| 4000 | 43.587 ms | 0.094 ms |
| 16000 | 617.805 ms | 0.391 ms |
| 40000 | 3812.123 ms | 1.185 ms |

Before, setup scanned the whole pending list once per input, even when no deferred
callback ran. This prevents the owning thread from servicing its ready events and
timers. After, setup rescans only after a callback can actually change readiness.
There is still a linear scan per subsequent completion in the stdlib collector;
this change does not claim constant-time fan-in or change failure/order semantics.

The latest general baseline, [`../baseline-2026-10-28.md`](../baseline-2026-10-28.md),
has no equivalent large pending fan-in case and was on another machine, so its
absolute times are not compared. These are wall-clock measurements, not instruction
counts or a full-suite refresh. The benchmark is a profiling guide, not a CI timing
gate. Unit tests check correctness without a fragile elapsed-time threshold.

## 2026-11-10: waiting in creation order (#3492)

`sched::remove_pending` scanned the pending queue from the newest end, so waiting on
promises in creation order was quadratic. It now checks the oldest entry first.
Release `ms` built from main (`d1ea6ce`) and from the change; the benchmark built with
each, whole-process wall time including startup, alternating before/after runs,
medians (n = 15 per case, 9 for 40000 at `MS_THREADS=1`/4):

| Case (`count mode order`) | Threads | Before | After |
| --- | ---: | ---: | ---: |
| 40000 immediate ordered | 1 | 685.9 ms | 20.1 ms |
| 40000 immediate ordered | 4 | 214.3 ms | 223.2 ms |
| 1000 immediate ordered | 1 | 3.05 ms | 2.64 ms |
| 40000 immediate wait_all | 1 | 38.7 ms | 43.7 ms |
| 1000 jitter ordered / wait_all | 1 | 9.82 / 10.24 ms | 9.59 / 9.85 ms |

The three slower-looking cells are inside run-to-run noise: reruns with 31 to 61 pairs
gave 40000 wait_all at 1 thread 1.027x (IQR 14 ms on 41 ms), 1-promise ordered 1.009x
(1 thread) and 0.96x (4 threads), and 1000 jitter ordered at 4 threads 1.003x. With
four threads the ordered case is dominated by cross-thread scheduling, not this scan.
The change adds one id comparison for a promise that is not at the front. Machine:
shared Linux x86-64 VM; wall-clock, not instruction counts.
