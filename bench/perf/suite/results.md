# Suite results

## 2026-11-25, split loops without a list (on `70c893f162`)

Release `ms` built from `70c893f162` with and without the split-loop change, same 4 vCPU Xeon VM, wall time in ms (min of 9) with the Rust program of the suite beside it. `for piece in text.split(sep)` walks the text by byte offset instead of building the list of pieces first. Programs with no split loop (csvgroup, wordfreq, jsonsum) moved by +3.8% to +7.8% between the two runs, which is this VM's noise.

| program | before | after | change | Rust |
|---|---:|---:|---:|---:|
| grep | 44.5 | 35.1 | -21% | 26.8 |
| report | 186.6 | 150.4 | -19% | 118.2 |
| treegrep | 32.6 | 25.8 | -21% | 19.8 |
| sortrecords | 287.5 | 245.3 | -15% | 261.6 |
| logstats | 53.3 | 48.2 | -10% | 69.7 |
| dedupe | 326.1 | 317.1 | -3% | 484.1 |
| pargroup | 49.0 | 48.3 | -1% | 33.6 |

Page faults of grep fall from 9.4k to 5.7k and of report from 31k to 18k. Callgrind instructions rise on the split-heavy programs (grep +11%, treegrep +11%, pargroup +4.8%, report +2.3%): each piece is a call that reads both strings again. The loops are memory bound, so wall time is the measure here.

## 2026-11-25, after the take-twin, padding and index-check changes (`8ddeac9b65`)

Release `ms` built from `8ddeac9b65`, 4 vCPU Xeon VM, min of 7, wall time in ms, process start and output included. Instruction counts (callgrind) are the stable measure on this shared VM: against main before #7065, #7080, #7090 and #7097 they fell as follows.

| program | instructions before | after | change |
|---|---:|---:|---:|
| report | 2,225 M | 1,672 M | -25% |
| interp | 3,092 M | 2,744 M | -11% |
| graph | 691 M | 644 M | -6.7% |
| sim | 2,034 M | 1,945 M | -4.4% |
| workers | 1,205 M | 1,129 M | -6.4% |

#7065 (take-twin pass and `read_all`) measured grep -28%, wordfreq -26%, report -24% and logstats -14% in its own run; `report` above includes it. The `split` pre-count of #7084 (+24% grep on 22 MB) was limited to texts of 4 KiB or less in #7100. `pargroup`, `wordfreq` and `grep` run at or below Rust's instruction count; their wall-time gap is page faults from materialized lists (`wordfreq` 55.7k faults against 19.9k) and, for `pargroup`, the libuv pool hand-off per file.

| program | ms | Rust | Go | Node | C | ms / Rust |
|---|---:|---:|---:|---:|---:|---:|
| interp | 211 | 162 | 164 | 645 | - | 1.30x |
| graph | 302 | 273 | 437 | 1145 | - | 1.11x |
| objgraph | 354 | 337 | 324 | 617 | - | 1.05x |
| sim | 188 | 135 | 182 | 237 | - | 1.39x |
| dispatch | 322 | 296 | 1098 | 1103 | - | 1.09x |
| hashing | 172 | 141 | 237 | 207 | - | 1.22x |
| lz | 194 | 153 | 567 | 627 | - | 1.27x |
| exprparse | 760 | 720 | 1083 | 1096 | - | 1.06x |
| logstats | 60 | 76 | 264 | 297 | 54 | 0.79x |
| csvgroup | 103 | 287 | 439 | 799 | 56 | 0.36x |
| wordfreq | 309 | 163 | 1064 | 1284 | 180 | 1.90x |
| sortrecords | 233 | 297 | 621 | 1232 | 320 | 0.78x |
| grep | 44 | 26 | 190 | 133 | 27 | 1.69x |
| treegrep | 25 | 20 | 44 | 62 | 22 | 1.25x |
| pargroup | 46 | 27 | 42 | 112 | 18 | 1.70x |
| jsonsum | 161 | 239 | 668 | 203 | 185 | 0.67x |
| dedupe | 258 | 523 | 536 | 985 | 319 | 0.49x |
| report | 207 | 123 | 406 | 1038 | 159 | 1.68x |
| workers | 35 | 30 | 31 | 254 | - | 1.17x |
| strings | 117 | 197 | 239 | 733 | - | 0.59x |
| concat | 8 | 9 | 7649 | 44 | - | 0.89x |
| jsonrt | 1047 | - | 1549 | 584 | - | - |
| regex | 411 | - | 1631 | 372 | - | - |

## 2026-11-15, after the wave of merges (`d85da123`)

Rerun on `d85da123` (main after #4034, with #4008, #4009, #4010, #4012 and #4013 merged; #4003 and #4004 still open), same VM, min of 5. Wall times were 0 to 50% higher than the `71487c98` run an hour earlier (`interp` 134 to 202 ms), but the callgrind instruction counts of `interp`, `strings`, `lz` and `graph` are unchanged to the instruction (within 1,000 of 2.98G, 1.76G, 618M and 635M), so the generated code and runtime path of these programs did not change; the wall-clock moves are VM load. Not rerun under callgrind: the other 19 programs. Open risk: #4032 (`wait_all` ends at the first failure) costs about 40% more on 100,000 trivial promises in its own debug-build numbers; rerun `workers` and `bench/perf/wait-all` in release when it merges.

## 2026-11-15, regression check on `71487c98`

Same-machine A/B: release `ms` built from `d4006e73` (2026-11-13 22:42 -0800, the commit of the 2026-11-14 baseline below) and from `71487c98` (main after #3996), both built and run in one session on this 4 vCPU Xeon 2.1 GHz VM, Manuscript column only, min of 5 (process start and I/O included, compile excluded). The 2026-11-14 tables below came from another session, so their absolute times are not compared; the speedups below are within this one session. `pargroup` did not build on `d4006e73` in this harness (it imports `resilience.ms`, renamed from `flow.ms` in #3959), so it has no base time.

| program | `d4006e73` | `71487c98` |
|---|---:|---:|
| interp | 190 | 134 |
| graph | 239 | 234 |
| objgraph | 256 | 227 |
| sim | 130 | 146 |
| dispatch | 249 | 202 |
| hashing | 138 | 140 |
| lz | 187 | 159 |
| exprparse | 644 | 488 |
| logstats | 67 | 66 |
| csvgroup | 131 | 134 |
| wordfreq | 209 | 209 |
| sortrecords | 289 | 188 |
| grep | 39 | 36 |
| treegrep | 116 | 32 |
| pargroup | - | 21 |
| jsonsum | 192 | 144 |
| dedupe | 290 | 253 |
| report | 194 | 122 |
| jsonrt | 540 | 535 |
| regex | 321 | 293 |
| workers | 55 | 38 |
| strings | 230 | 143 |
| concat | 428 | 9 |

No program is slower beyond noise. The two largest apparent slowdowns were checked with callgrind, which does not vary with machine load: `graph` +0.1% instructions (634.4M against 635.2M), `sim` +0.8% (936.9M against 944.5M); 9 alternating wall-clock runs of `sim` overlap (131 to 184 ms against 137 to 210 ms). The gains are not bisected; likely sources from the day's merge titles: `treegrep` -72% (inline file reads for local promises, #3932 and the scheduler changes), `strings` -38% and `report` -37% (string work, #3955, #3956, #3957), `sortrecords` -35%, `concat` -98% (in-place string append). Wait-group promise changes (#3972) account for `workers` -31%, and `interp` -29% and `exprparse` -24% come from the compiler changes of the day (#3910, #3927, #3949).

Instruction counts for the nightly gate (`make perf-counts`, `bench/perf/counts.txt`): interp 2,983.6M, strings 1,757.3M, lz 618.3M, graph 635.2M.

## 2026-11-14, Go and Node for the text, data and file programs

`81a9844b`, same machine and method (min of 2). The ten programs that moved in from `engineering/` now have Go and Node versions; every output matches the C and Rust output. Go and Node use their standard libraries (`encoding/json`, `JSON.parse`, `strings`, `Map`), so `jsonsum` compares Manuscript's typed parse against their generic parse.

| program | ms | rust | go | node | c | ms / rust | ms / go | ms / node |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| logstats | 63 | 82 | 307 | 397 | 58 | 0.77x | 0.21x | 0.16x |
| csvgroup | 173 | 331 | 600 | 1280 | 69 | 0.52x | 0.29x | 0.14x |
| wordfreq | 267 | 243 | 1207 | 1512 | 257 | 1.10x | 0.22x | 0.18x |
| sortrecords | 281 | 296 | 789 | 1342 | 339 | 0.95x | 0.36x | 0.21x |
| grep | 35 | 32 | 274 | 155 | 29 | 1.09x | 0.13x | 0.23x |
| **treegrep** | 93 | 31 | 49 | 75 | 32 | **3.00x** | **1.90x** | 1.24x |
| pargroup | 47 | 40 | 50 | 196 | 24 | 1.18x | 0.94x | 0.24x |
| jsonsum | 185 | 294 | 897 | 278 | 223 | 0.63x | 0.21x | 0.67x |
| dedupe | 299 | 507 | 535 | 971 | 315 | 0.59x | 0.56x | 0.31x |
| report | 167 | 166 | 538 | 1332 | 214 | 1.01x | 0.31x | 0.13x |

Only `treegrep` is slower than Go and Node as well as Rust and C: Go walks the same tree in 49 ms and Node in 75 ms against 93 ms. That makes the directory-walk gap a Manuscript cost, not an operating system floor.

## 2026-11-14 baseline

`d4006e73`, Release `ms` from `make build`, gcc 13.3 `-O2`, rustc 1.99.1 `-O`, Go 1.24.7, Node 22.23, 4 vCPU Xeon 2.1 GHz VM, min of 5. Ratios are Manuscript time over the other language's time, so below 1.00x is faster.

| program | ms | rust | go | node | c | ms / rust | ms / go |
|---|---:|---:|---:|---:|---:|---:|---:|
| interp | 215 | 253 | 218 | 769 | - | 0.85x | 0.99x |
| graph | 221 | 280 | 426 | 1054 | - | 0.79x | 0.52x |
| objgraph | 261 | 360 | 347 | 647 | - | 0.72x | 0.75x |
| sim | 187 | 171 | 218 | 307 | - | 1.09x | 0.86x |
| dispatch | 256 | 319 | 1381 | 1182 | - | 0.80x | 0.19x |
| hashing | 143 | 148 | 321 | 287 | - | 0.97x | 0.45x |
| lz | 186 | 183 | 558 | 674 | - | 1.02x | 0.33x |
| exprparse | 793 | 978 | 1170 | 1366 | - | 0.81x | 0.68x |
| regex | 342 | - | 1937 | 453 | - | - | 0.18x |
| jsonrt | 554 | - | 1991 | 806 | - | - | 0.28x |
| strings | 227 | 215 | 281 | 930 | - | 1.06x | 0.81x |
| **concat** | 483 | 11 | 6739 | 63 | - | **43.91x** | 0.07x |
| **workers** | 944 | 296 | 503 | 670 | - | **3.19x** | 1.88x |
| logstats | 65 | 87 | - | - | 58 | 0.75x | - |
| csvgroup | 206 | 347 | - | - | 73 | 0.59x | - |
| wordfreq | 245 | 252 | - | - | 242 | 0.97x | - |
| sortrecords | 308 | 268 | - | - | 382 | 1.15x | - |
| grep | 41 | 31 | - | - | 31 | 1.32x | - |
| **treegrep** | 94 | 26 | - | - | 28 | **3.62x** | - |
| pargroup | 45 | 30 | - | - | 20 | 1.50x | - |
| jsonsum | 159 | 279 | - | - | 230 | 0.57x | - |
| dedupe | 222 | 354 | - | - | 281 | 0.63x | - |
| report | 179 | 164 | - | - | 174 | 1.09x | - |

Of the 21 programs with a Rust version, Manuscript is ahead on 11 and within 1.1x on 4 more; it is ahead of Go on every program except `interp` (level) and `workers`, and ahead of Node on all but `concat`. The gaps are concentrated in a few places:

1. **Appending to a string with `+=` is quadratic unless the right side is a literal** (`concat`). Per 200k appends to one string: `s += "item,"` 5 ms, `s += i.to_string()` 3.1 s, `s += "item-{i},"` 13.3 s. Rust and Node append in place (the whole program at 50k appends per pattern: Rust 11 ms, Node 63 ms, Manuscript 483 ms). Go is quadratic too (6.7 s), so this matches Go's behavior but not Rust's or Node's; `t = t + x` is just as slow.
2. **Many small promises get slower with more threads** (`workers`). 100k promises of about 1 us of work take 105 ms with `MS_THREADS=1` and 470 to 600 ms on 4 threads; Go runs 100k goroutines in about 200 ms. The CPU-bound half (16 chunks) scales 3.5x on 4 threads and is within about 1.4x of Rust's threads.
3. **Walking a directory tree and reading many small files** (`treegrep` 3.6x, `pargroup` 1.5x against C and Rust): file and directory calls go through the blocking pool and a promise per call.
4. **A `var` cursor over a linked list copies the tail on every step.** `cur = l.next` in a `while` loop over a 20k-node list takes 10 s and 40k nodes 42 s (quadratic); a recursive walk of 1M nodes takes 30 ms. `objgraph` uses the recursive walk. This is not in the table because the suite program avoids it; it is a bug to fix, with the loop as the regression case.
5. Smaller: `grep` 1.3x (input path), `sortrecords` 1.15x, `report` 1.09x, `sim` 1.09x.

`regex`, `jsonrt` and `strings` compare against Go and Node because Rust's `std` has no regex or JSON; Rust sources exist only where `std` can do the job. `hashing` and `lz` use `List[Int]` for bytes in Manuscript, Go and Rust alike so all four languages move the same amount of memory. `workers` runs Node's CPU half on worker threads and its small tasks as promises on the main thread.

## 2026-11-14: waiting on a local promise no longer sends a file read to the blocking pool

Same machine and suite, min of 9, strace counts for `treegrep` on the 2005-file tree.

`promise(fn: ..., Placement.Here)` created its waiter's token as remote, so a blocking call inside the work saw a waiter another thread might wake and handed every `read_file` to the pool (2 futex, 1 epoll_wait, 1 eventfd write per file). A promise started on this thread is now woken only from this thread, so a lone task reads inline. `read_file` also drops its second `fstat`.

| Program | before (ms) | after (ms) | C (ms) |
| --- | --- | --- | --- |
| treegrep | 90 | 33 | 27 |
| pargroup | 42 | 42 to 48 | 20 |

`treegrep` futex calls 3997 to 1, epoll_wait 2000 to 0. `pargroup` keeps its pool hand-off by design (four stripe tasks overlap I/O); its remaining gap is compute: one thread takes 73 ms, four take 48 ms.

Same day, second change (`pargroup`): a worker thread's root task waits for scheduler mail and a task that joins a local task waits for nothing else, but neither counted as stalled, so the four stripe tasks on worker threads still sent every read to the pool. Both now count, so `pargroup` reads inline on worker threads (epoll_wait 2005 to 505, futex 4097 to 1008). Median of 25 runs, noisy VM: `pargroup` 44 to 51 ms before, 35 to 42 ms after; Rust 27 to 32 ms, C 18 to 20 ms. `workers` is unchanged (836 ms against 944 ms in the first run, within noise).

Same day, third change: `String.split` starts its list with room for eight pieces (never more than the text can hold) instead of four, so a seven-field line no longer grows and copies its list once. `pargroup` on one thread: 940M to 780M instructions (callgrind, -17%). Conformance corpus: 3942 and 1458 fixtures pass.

Same day, fourth change: a split at a one-byte separator of a text up to 128 bytes (a record, a log line) finds every separator in one pass over eight-byte words instead of one search per piece. `pargroup` on one thread: 873M to 803M instructions (-8%); a control of five split shapes (record, two fields, 450-byte text with one separator, dense 400-byte, 20 KB) 2.05G to 1.92G. Longer texts keep the per-piece search: a 512-byte limit made the controls 9% worse (2.23G). Not done: a split read only by constant indexes could skip building the list, but the pieces cost about 90 instructions each and the finds would repeat per index, so the saving is below 15% on this program.

## 2026-11-14: name the `x86-64` CPU for `llc`

Same sandbox (4 cores). `llc` with no `-mcpu` (LLVM 23) no longer emits the 32-bit guard in front of a 64-bit `idiv`, so division and remainder of small values took the slow 64-bit path; `-mcpu=x86-64`, which rustc uses, restores it. Trial-division primes loop, 1 thread / 4 threads, median of 7: 1443 / 430 ms before, 920 / 288 ms after (Rust, 1 thread: 930 ms). Minimum of 5 in `run.sh`: `workers` 535 to 353 ms (Rust 251), `hashing` 156, `lz` 224, `interp` 157 (no regression against the table above). Remaining `workers` gap is the 100k small promises, which still do not scale past 1 thread (64 ms on 1 thread, 180 ms on 4).

## 2026-11-14: `workers` is now a realistic chunked workload

The old `workers` ran 16 prime-counting chunks and then 100k promises of about 1 us each, a stress test of task creation that no program resembles, against a Rust version with a different design. It is now 128 independent chunks that each generate 200,000 values, count them into 256 buckets and fold a checksum: the same loop in Manuscript (a promise per chunk), Rust (one worker per core pulling chunk numbers), Go (a goroutine per chunk) and Node (a worker thread per core). The 100k-promise stress test stays in `bench/perf/small-promises`.

`ms` from `make build` on main, 4 vCPU Xeon VM, min of 7: ms 49 ms, Rust 30, Go 33, Node 279. ms / Rust 1.63x, ms / Go 1.48x. By threads (min of 9): ms 173 / 84 / 51 ms on 1 / 2 / 4 threads, Rust 125 ms pinned to one core and 32 ms on 4, so scaling is fine (3.4x) and the gap is the loop itself (1.4x at one thread).
## 2026-11-14: a list updated in place in a loop is registered once

Same sandbox (4 cores). The `workers` chunk loop (200,000 steps updating a 256-bucket list) inside a promise registered and discarded an unwind cleanup for the list on every iteration. It is now registered once before the loop. One thread: promise 185 ms to 113 ms (min of 7); the same loop called directly is 113 ms (Rust 101 ms on one core). Callgrind: 3.51G to 1.21G instructions. Conformance: 3964 and 1458 fixtures pass on Cranelift and LLVM.

## 2026-11-25: list fusion matches fault exits

Callgrind instruction counts, `ms` built from this branch against its parent, same machine (4 vCPU VM): `graph` 619.4M to 558.6M (-9.8%); a `map`/`filter`/`sum` chain over 1000 `Int` repeated 2000 times 62.9M to 24.9M; `hashing` 1177M to 1220M (+3.6%, wall time equal, the change is in `sha256`'s LLVM schedule after fewer unwinding tests); `csvgroup`, `dispatch`, `exprparse`, `interp`, `lz`, `sim`, `sortrecords`, `wordfreq` within 0.2%. `wordfreq` and `report` build lists of `String` pieces, which fusion does not take yet.
