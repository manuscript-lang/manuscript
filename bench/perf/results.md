# Performance results

The one results page of the suite ([groups.txt](groups.txt), [README](README.md)): each section is a group, newest dated run first. Rerun a group and add a dated section; do not edit old numbers. Compare numbers only from one machine.

## suite

_Whole programs against rust, go, node and c. Run: `make perf GROUP=suite`._

### 2026-11-25, split loops without a list (on `70c893f162`)

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

### 2026-11-25, after the take-twin, padding and index-check changes (`8ddeac9b65`)

Release `ms` built from `8ddeac9b65`, 4 vCPU Xeon VM, min of 7, wall time in ms, process start and output included. Instruction counts (callgrind) are the stable measure on this shared VM: against main before #7065, #7080, #7090 and #7097 they fell as follows.

| program | instructions before | after | change |
|---|---:|---:|---:|
| report | 2,225 M | 1,672 M | -25% |
| interp | 3,092 M | 2,744 M | -11% |
| graph | 691 M | 644 M | -6.7% |
| sim | 2,034 M | 1,945 M | -4.4% |
| workers | 1,205 M | 1,129 M | -6.4% |

##7065 (take-twin pass and `read_all`) measured grep -28%, wordfreq -26%, report -24% and logstats -14% in its own run; `report` above includes it. The `split` pre-count of #7084 (+24% grep on 22 MB) was limited to texts of 4 KiB or less in #7100. `pargroup`, `wordfreq` and `grep` run at or below Rust's instruction count; their wall-time gap is page faults from materialized lists (`wordfreq` 55.7k faults against 19.9k) and, for `pargroup`, the libuv pool hand-off per file.

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

### 2026-11-15, after the wave of merges (`d85da123`)

Rerun on `d85da123` (main after #4034, with #4008, #4009, #4010, #4012 and #4013 merged; #4003 and #4004 still open), same VM, min of 5. Wall times were 0 to 50% higher than the `71487c98` run an hour earlier (`interp` 134 to 202 ms), but the callgrind instruction counts of `interp`, `strings`, `lz` and `graph` are unchanged to the instruction (within 1,000 of 2.98G, 1.76G, 618M and 635M), so the generated code and runtime path of these programs did not change; the wall-clock moves are VM load. Not rerun under callgrind: the other 19 programs. Open risk: #4032 (`wait_all` ends at the first failure) costs about 40% more on 100,000 trivial promises in its own debug-build numbers; rerun `workers` and `bench/perf/wait-all` in release when it merges.

### 2026-11-15, regression check on `71487c98`

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

### 2026-11-14, Go and Node for the text, data and file programs

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

### 2026-11-14 baseline

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

### 2026-11-14: waiting on a local promise no longer sends a file read to the blocking pool

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

### 2026-11-14: name the `x86-64` CPU for `llc`

Same sandbox (4 cores). `llc` with no `-mcpu` (LLVM 23) no longer emits the 32-bit guard in front of a 64-bit `idiv`, so division and remainder of small values took the slow 64-bit path; `-mcpu=x86-64`, which rustc uses, restores it. Trial-division primes loop, 1 thread / 4 threads, median of 7: 1443 / 430 ms before, 920 / 288 ms after (Rust, 1 thread: 930 ms). Minimum of 5 in `run.sh`: `workers` 535 to 353 ms (Rust 251), `hashing` 156, `lz` 224, `interp` 157 (no regression against the table above). Remaining `workers` gap is the 100k small promises, which still do not scale past 1 thread (64 ms on 1 thread, 180 ms on 4).

### 2026-11-14: `workers` is now a realistic chunked workload

The old `workers` ran 16 prime-counting chunks and then 100k promises of about 1 us each, a stress test of task creation that no program resembles, against a Rust version with a different design. It is now 128 independent chunks that each generate 200,000 values, count them into 256 buckets and fold a checksum: the same loop in Manuscript (a promise per chunk), Rust (one worker per core pulling chunk numbers), Go (a goroutine per chunk) and Node (a worker thread per core). The 100k-promise stress test stays in `bench/perf/small-promises`.

`ms` from `make build` on main, 4 vCPU Xeon VM, min of 7: ms 49 ms, Rust 30, Go 33, Node 279. ms / Rust 1.63x, ms / Go 1.48x. By threads (min of 9): ms 173 / 84 / 51 ms on 1 / 2 / 4 threads, Rust 125 ms pinned to one core and 32 ms on 4, so scaling is fine (3.4x) and the gap is the loop itself (1.4x at one thread).
### 2026-11-14: a list updated in place in a loop is registered once

Same sandbox (4 cores). The `workers` chunk loop (200,000 steps updating a 256-bucket list) inside a promise registered and discarded an unwind cleanup for the list on every iteration. It is now registered once before the loop. One thread: promise 185 ms to 113 ms (min of 7); the same loop called directly is 113 ms (Rust 101 ms on one core). Callgrind: 3.51G to 1.21G instructions. Conformance: 3964 and 1458 fixtures pass on Cranelift and LLVM.

### 2026-11-25: list fusion matches fault exits

Callgrind instruction counts, `ms` built from this branch against its parent, same machine (4 vCPU VM): `graph` 619.4M to 558.6M (-9.8%); a `map`/`filter`/`sum` chain over 1000 `Int` repeated 2000 times 62.9M to 24.9M; `hashing` 1177M to 1220M (+3.6%, wall time equal, the change is in `sha256`'s LLVM schedule after fewer unwinding tests); `csvgroup`, `dispatch`, `exprparse`, `interp`, `lz`, `sim`, `sortrecords`, `wordfreq` within 0.2%. `wordfreq` and `report` build lists of `String` pieces, which fusion does not take yet.

## programs

_One operation per loop against go and rust. Run: `make perf GROUP=programs`._

### main at c1b81215 (2026-10-25)

Median of 5 alternating runs; linux/amd64, four cores, Go 1.24.7, rustc 1.99.1; ns/op; checksums and operation counts verified. Same caveats as below: Manuscript checks Int overflow and list bounds, "Rust, overflow checks" is the closest like-for-like, and "0.00" means LLVM folded the loop to a constant.

| operation | ops | Manuscript | Go | Rust | Rust, overflow checks | ms / Go | ms / Rust | ms / Rust, overflow checks |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| string_append_50k | 50000 | 5.12 | 4.15 | 1.28 | 1.14 | 1.23x | 3.99x | 4.51x |
| read_line | 200000 | 105.14 | 80.30 | 58.36 | 66.42 | 1.31x | 1.80x | 1.58x |
| map_put_get_8k | 16000 | 35.08 | 30.37 | 40.36 | 39.54 | 1.15x | 0.87x | 0.89x |
| int_eq | 10000000 | 0.67 | 0.80 | 0.66 | 0.92 | 0.84x | 1.01x | 0.73x |
| generic_call | 100000000 | 0.33 | 0.67 | 0.34 | 0.33 | 0.50x | 0.97x | 1.00x |
| method_call | 100000000 | 0.00 | 0.50 | 1.69 | 1.50 | 0.00x | 0.00x | 0.00x |
| try | 100000000 | 0.34 | 0.70 | 0.88 | 0.81 | 0.49x | 0.38x | 0.42x |
| match | 100000000 | 1.56 | 2.12 | 1.16 | 1.60 | 0.74x | 1.34x | 0.97x |
| builtin_length | 100000000 | 0.00 | 0.33 | 0.33 | 0.35 | 0.00x | 0.00x | 0.00x |
| for_list | 100000000 | 0.44 | 0.62 | 0.28 | 0.41 | 0.72x | 1.56x | 1.07x |

Faster than Go on 7 of 10 rows (two fold to constants), slower on string_append (1.2x), read_line (1.3x) and map_put_get (1.15x). Against Rust with overflow checks it is level or ahead on 6 rows and behind on string_append (4.5x: a runtime call per append against an inlined push) and read_line (1.6x).

### Latest: Rust `ms` (2026-10-22)

Median of 7 runs with alternating order; linux/amd64, four cores, Go 1.24.7, rustc 1.99.1 (`-C opt-level=3 -C codegen-units=1`). Checksums and operation counts verified. Ratios are Manuscript time over the other language's time, so below 1.00x is faster than it.

**Read the Rust columns with the caveats.** Manuscript checks Int overflow and list bounds; Go and Rust (release) check only bounds. "Rust, overflow checks" is the same source built with `-C overflow-checks=on`, the closest like-for-like. "folded" means LLVM folded the loop to a constant, so no time is reported; the Go and Manuscript columns still do the work.

| operation | ops | Manuscript | Go | Rust | Rust, overflow checks | ms / Go | ms / Rust | ms / Rust, overflow checks |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| string_append_50k | 50000 | 6.20 | 4.44 | 1.18 | 1.65 | 1.40x | 5.24x | 3.76x |
| read_line | 200000 | 135.43 | 112.91 | 67.79 | 69.89 | 1.20x | 2.00x | 1.94x |
| map_put_get_8k | 16000 | 41.19 | 40.09 | 45.24 | 60.43 | 1.03x | 0.91x | 0.68x |
| int_eq | 10000000 | 0.84 | 1.30 | 1.06 | 1.05 | 0.64x | 0.79x | 0.80x |
| generic_call | 100000000 | 0.63 | 0.69 | 0.50 | 0.55 | 0.91x | 1.27x | 1.16x |
| method_call | 100000000 | 0.00 | 2.30 | 1.82 | 2.07 | 0.00x | 0.00x | 0.00x |
| try | 100000000 | 0.66 | 0.80 | 0.73 | 0.79 | 0.83x | 0.92x | 0.84x |
| match | 100000000 | 1.69 | 2.17 | 1.71 | 1.89 | 0.78x | 0.99x | 0.90x |
| builtin_length | 100000000 | 0.00 | 0.32 | 0.35 | 0.33 | 0.00x | 0.00x | 0.00x |
| for_list | 100000000 | 0.52 | 1.06 | 0.30 | 0.51 | 0.49x | 1.75x | 1.02x |

Release builds use LLVM (bundled `opt`/`llc`, `-O3`). Manuscript is faster than Go on 7 of 10 rows (method_call and builtin_length fold to constants), ties on map_put_get and is slower on string_append (1.4x) and read_line (1.2x). Against Rust with overflow checks it is slower on string_append (3.8x: a call per append against an inlined push), read_line (1.9x) and generic_call (1.2x), and level or ahead elsewhere; for_list is level with checks on. Whole-program kernels: see [`../kernels/README.md`](../kernels/README.md) and [`../competence/README.md`](../competence/README.md).

### 2026-11-03, refcount removal

`bench_read_line` now reads `lines(stdin())`. Min of three 15-run passes per binary, `d34af765` against `d6052382`: every row within 1.13x, including `int_eq`, which touches no object, so the spread is the VM's noise. Table in [refcount-removal-2026-11-03.md](../refcount-removal-2026-11-03.md).

## workloads

_Agent-style programs on stdin against go and rust. Run: `make perf GROUP=workloads`._

Ordinary agent-style programs (the reference solutions of the small agent challenges in `bench/agent/challenges`) on about 3 MB of stdin each, built with `ms build` (Release, LLVM), `go build` and `rustc -O`. Outputs are compared byte for byte; the time is the best wall time of 3 runs in milliseconds. Reproduce with `MS=./target/release/ms sh bench/perf/workloads/run.sh 3`; compare only runs from one machine.

The current runner checks every language's output in an untimed warm-up and every
timed trial, rotates version order, and rejects any nonzero producer status or
output mismatch before publishing a table. It uses a monotonic clock with
sub-millisecond precision. Times exclude compilation and validation but include
process startup, stdin and stdout. Go builds disable VCS stamping. With
`BENCH_OUTPUT=.artifacts/workloads`, each run retains its sources, binaries, inputs,
expected output and `samples.json` (raw nanoseconds and input/output/binary hashes).
A failed suite leaves no final `table.txt`; a pending table is incomplete evidence.
Run the regression tests with
`python3 -m unittest discover -s bench/perf/workloads -p test_measure.py`.
The [2026-10-29 validation controls](validation-2026-10-29.md) record the failure
reproductions, release settings and paired native samples. Historical results
below retain their original measurement method; this validation fix makes no
generated-program speedup claim.

### main at b4b25a2b plus the filtered-loop walk (2026-11-18)

linux/amd64, four shared vCPUs, Go 1.24.7, rustc 1.99.1 `-O`, `ms` Release build (LLVM); minimum of 3, milliseconds, 3 MB of each program's largest hidden stdin. The ten Manuscript reference programs had stopped compiling after the `get` and `slice` changes, so they were ported first (`.get(d)` to `.get_or(d)`, `.slice(a, b).get()` to `.slice(a, b)`); the table includes the change that makes `for x in xs.filter(f)` walk `xs` in place (c13).

| program | ms | go | rust | ms / go | ms / rust |
|---|---:|---:|---:|---:|---:|
| c03-csv-group-sum | 38.5 | 37.1 | 26.4 | 1.04x | 1.45x |
| c05-calculator | 42.3 | 48.1 | 146.9 | 0.88x | 0.29x |
| c09-ciphers | 50.6 | 59.8 | 38.5 | 0.85x | 1.31x |
| c13-inventory-orders | 190.9 | 260.0 | 125.8 | 0.73x | 1.52x |
| c14-dp-suite | 553.5 | 1631.2 | 377.0 | 0.34x | 1.47x |
| c16-maze-bfs | 75.3 | 38.4 | 41.3 | 1.96x | 1.82x |
| c18-cron-next-runs | 680.5 | 976.5 | 743.2 | 0.70x | 0.92x |
| c25-log-analyzer | 19.1 | 52.6 | 18.1 | 0.36x | 1.05x |
| c36-bank-ledger | 74.5 | 115.8 | 63.0 | 0.64x | 1.18x |
| c44-unified-diff | 14.7 | 67.1 | 14.4 | 0.22x | 1.02x |

Re-measured after the table: c14-dp-suite is not 1.47x. The table's Rust time (377 ms) was one fast sample on a noisy shared VM; 21 alternating runs of the same 3 MB input, user plus system CPU time, give ms 518 ms (median 569) against Rust 627 ms (median 672), so 0.83x. Callgrind agrees: 660M instructions for ms against 955M for Rust on 300 KB. The other ratios in the table carry the same noise of up to about 1.4x; rerun a program alone with alternating samples before treating it as a gap. A three-way comparison folded to one compare in MIR (`a.max(b)` over `Int`) changed nothing in the release build: LLVM already did it (660,254,501 instructions both ways), so that rule was not kept.

c13 alone, 11 runs on the unchanged tree and then with the change: 166 ms to 162 ms best, 210 ms to 193 ms median (Rust 129 ms); callgrind on 400 KB of input: 392M to 350M instructions (Rust 215M).

### main at c1b81215 (2026-10-25)

linux/amd64, four cores, Go 1.24.7, rustc 1.99.1.

| program | Manuscript | Go | Rust | ms / Go | ms / Rust |
|---|---:|---:|---:|---:|---:|
| c03-csv-group-sum | 63 | 44 | 37 | 1.43x | 1.70x |
| c05-calculator | 46 | 48 | 98 | 0.96x | 0.47x |
| c09-ciphers | 63 | 61 | 33 | 1.03x | 1.91x |
| c13-inventory-orders | 118 | 248 | 143 | 0.48x | 0.83x |
| c14-dp-suite | 631 | 1431 | 645 | 0.44x | 0.98x |
| c16-maze-bfs | 31 | 39 | 32 | 0.79x | 0.97x |
| c18-cron-next-runs | 809 | 1052 | 807 | 0.77x | 1.00x |
| c25-log-analyzer | 28 | 60 | 21 | 0.47x | 1.33x |
| c36-bank-ledger | 97 | 109 | 63 | 0.89x | 1.54x |
| c44-unified-diff | 3 | 65 | 15 | 0.05x | 0.20x |

Manuscript is faster than Go on 8 of 10 programs and level on the ciphers; Go is clearly ahead only on the CSV grouping (1.43x). Against Rust it is level or ahead on 6 of 10; the four behind it are string-heavy (CSV splitting, per-character ciphers, log parsing and ledger formatting), where the remaining costs are `f"{int}"` formatting and scalar counting on short strings (see the data-types audit in the repository history for the callgrind breakdown).

### 2026-11-03, refcount removal

The reference solutions were ported from the removed `read_line`/`flush` API to `lines(stdin())` and `flush().wait()`. Min of two rounds of 5 on `d34af765` (refcounts, streams redesign) against `d6052382` (no refcounts): the ten programs read 0.94x to 1.09x with the Go and Rust columns moving as much, so no regression beyond noise. Table in [refcount-removal-2026-11-03.md](../refcount-removal-2026-11-03.md).

### 2026-11-07, suite rebuilt after the streams change

The ten reference solutions stopped building after [#2726](https://github.com/manuscript-lang/manuscript/pull/2726) (`input.read().wait()` is now `input.next()`, `flush()` returns its `Result`); they are ported again. Revision `4e8da342` plus the `String.from_scalars` change, Release LLVM build, min of 5, same shared 4 vCPU Xeon VM as above.

| program | ms ms | go ms | rust ms | ms/go | ms/rust |
|---|---:|---:|---:|---:|---:|
| c03-csv-group-sum | 71.8 | 45.1 | 33.8 | 1.59x | 2.12x |
| c05-calculator | 150.1 | 53.2 | 142.0 | 2.82x | 1.06x |
| c09-ciphers | 128.3 | 61.7 | 43.1 | 2.08x | 2.98x |
| c13-inventory-orders | 366.9 | 303.6 | 168.9 | 1.21x | 2.17x |
| c14-dp-suite | 768.4 | 1593.5 | 511.4 | 0.48x | 1.50x |
| c16-maze-bfs | 24.9 | 35.7 | 35.8 | 0.70x | 0.69x |
| c18-cron-next-runs | 1789.0 | 1188.3 | 831.5 | 1.51x | 2.15x |
| c25-log-analyzer | 23.8 | 48.4 | 24.1 | 0.49x | 0.99x |
| c36-bank-ledger | 85.8 | 126.4 | 70.0 | 0.68x | 1.23x |
| c44-unified-diff | 2.9 | 64.6 | 16.7 | 0.04x | 0.17x |

Worst gaps to work on next: c09 (3x Rust), c18, c03, c13 (2x Rust), c05 (2.8x Go).

`c09-ciphers` under callgrind (300 KB input, 43.7M instructions before): `String.from_scalars` took 3.8M, built a `Vec`, then copied it into the string. An all-ASCII list now narrows straight into the result (2.4M, whole program 41.4M, -5%; 100-scalar call 142 to 80 ns). Wall-clock moved 134 to 128 ms, inside the noise. The rest of the profile is spread thin: the compiled `transform` loop 25%, `owned_copy` 8%, `sub_scalars`, `replace`, `slice`, `realloc` 3-4% each.

Profiling note: callgrind cannot map the 256 GiB allocator reservation, so `ensure_region` fails and every allocation goes to glibc `malloc` (it made `c09` look malloc-bound at 68M instructions). Shrink `PAGES_SIZE` and `GROW_CHUNKS` in `crates/ms-rt/src/alloc.rs` locally for a profile run and do not commit the change.

### 2026-11-07, closing `stdout()` no longer flushes

`stdout()` returns a new stream per call and a temporary stream closes its sink when it dies, so `try stdout().write(...)` ran `msrt_io_flush` after every write: one `write` system call per output line (863,660 for c18 at 3 MB of input, 17 bytes each). The reference programs for Go and Rust buffer their output. `Stdout.close` now leaves the process-wide buffer alone; it is flushed by `flush()`, at exit, before a child process starts, before anything is written to standard error, and on a trap or fault. Same machine and method as the section above, min of 5, revision `a12e611b` plus this change.

| program | before ms | after ms | go ms | rust ms | ms/go | ms/rust |
|---|---:|---:|---:|---:|---:|---:|
| c03-csv-group-sum | 71.8 | 72.2 | 46.9 | 33.3 | 1.54x | 2.17x |
| c05-calculator | 150.1 | 58.0 | 56.1 | 134.0 | 1.03x | 0.43x |
| c09-ciphers | 128.3 | 58.6 | 62.0 | 42.8 | 0.94x | 1.37x |
| c13-inventory-orders | 366.9 | 142.6 | 291.0 | 168.7 | 0.49x | 0.85x |
| c14-dp-suite | 768.4 | 663.4 | 1639.7 | 521.0 | 0.40x | 1.27x |
| c16-maze-bfs | 24.9 | 26.9 | 36.7 | 38.6 | 0.73x | 0.70x |
| c18-cron-next-runs | 1789.0 | 883.6 | 1199.7 | 846.8 | 0.74x | 1.04x |
| c25-log-analyzer | 23.8 | 23.5 | 62.2 | 23.8 | 0.38x | 0.99x |
| c36-bank-ledger | 85.8 | 89.2 | 139.6 | 71.7 | 0.64x | 1.24x |
| c44-unified-diff | 2.9 | 3.2 | 85.3 | 15.9 | 0.04x | 0.20x |

The earlier "c05 is 2.8x Go" and "c09 is 3x Rust" gaps were this syscall cost, not computation: `c18` under callgrind ran 884M instructions against Rust's 837M. The workloads harness reads output through a pipe, which is what made the per-write flush expensive; with stdout sent to `/dev/null` the gap was only 1.2x. Biggest remaining gaps: c03 (2.2x Rust, `split` and `find` on one-byte separators), c09 and c36 (1.2-1.4x Rust).

### 2026-11-07, texts built by `StringBuilder`, `repeat` and `replace` keep the ASCII flag

A heap string carries an ASCII flag so `length`, `get` and `slice` need not count scalars. `StringBuilder.build` (and so `List.join`), `String.repeat` and `String.replace` produced unflagged strings, so each `length()` or `get(i)` on a 17 KB result rescanned it (235 ns per call). The stdlib suite against `baseline-2026-10-28.md` showed it as `string.index_char_at` 10.7 to 217 ns; after the change it is 7.6 ns. `msrt_strbuilder_freeze`, `msrt_string_repeat` and `fill_replaced` now flag an ASCII result (one vector scan for the builder).

Other cases that read 2x or worse against that baseline on 2026-11-07 and reproduce when rerun alone, not fixed here: `fs.read_file_64k` 8 to 63 us (`read_file` returns a promise, so the program has two tasks and `offload` hands every read to a pool thread: two thread wake-ups per call instead of an inline read), `fs.write_file_64k` 138 to 220 us (same cause), `json.navigate` 49 to 105 ns (`Map.get` through `JsonValue.get` clones each value; callgrind shows 200k `slot_copy` calls per 100k iterations). `list.max_by_loop` 47.7 to 109 us is not a regression: the benchmark changed from `for p in points: if p.y > best.y: best = p` to an indexed loop that loads two elements per iteration, and the indexed loop runs at the same 1.1 ns per iteration on builds from 2026-10-31 to today (reading the value once is 2.5x faster, so the range pass not proving `best` in range is a possible improvement).

### 2026-11-07, blocking file calls run inline when every other task is parked

`read_file(path).wait()` runs its work in a task, so the program has two tasks and `pool::alone()` (task count at most 1) was false: every whole-file read and write was handed to a pool thread and back, two thread wake-ups. A 64 KiB `read_file(...).wait()` took 48 us, of which the read is under 9 us (`fs.read_file_64k` 8.2 to 63 us against `baseline-2026-10-28.md`). `alone()` now also holds when every other task is parked on a token with no deadline and no descriptor, so nothing else could run during an inline call (`msrt_task_others_stalled`, checked only up to 4 tasks). `read_file` 64 KiB: 48.0 us to 8.6 us. Programs with another runnable task, a timer or a descriptor wait still offload. `fs.write_file_64k` stays near 220 us: that is the file system's cost (truncate and write on this VM's `/tmp`), not the hop.

### 2026-11-07, a function returning `Map.get` borrows the entry

`JsonValue.get` returned `values.get(key)` through `msrt_map_get`, which deep-copies the value: the checker treated `m.get(k)` returned from a function as a new value, though the stdlib documents the result as a borrow. A returned `m.get(k)` is now a borrow of the receiver (the lowering reads the entry with `msrt_map_get_ptr` and returns `opt.view`), as `xs.get(i)` already was. `json.navigate` 105 to 57 ns (`bench/perf/stdlib`, 5 samples). Callers that hold the result while changing the map now need `.clone()` (two sites in `stdlib/data/toml.ms`); fixture `map-get-result-borrows-map`.

### 2026-11-07, round 9: compile time, peak memory, scaling probe (no change needed)

- Compile time: a hello-world `ms build` is 0.12 s warm (debug and release). A cold cache costs 3 to 4 s, which is the one-time download of the pinned LLVM tools archive, not compilation.
- Peak RSS (`VmHWM`, ~3 MB stdin) of the ten workloads, ms / Go / Rust in MB: c03 3.0/6.1/5.0, c05 3.0/5.9/2.1, c09 3.0/6.4/4.1, c13 3.2/7.0/9.8, c14 3.0/22.5/2.2, c16 28.0/18.9/27.3, c18 3.1/6.9/16.4, c25 9.2/11.5/5.9, c36 14.8/6.7/10.9, c44 3.2/26.3/12.7. The largest ratio is c36 at 2.2x Go (14.8 MB).
- Scaling probe (each operation at n, 4n and 16n): append, `sorted`, `Set`, `Map[Int, Int]`, `Map[String, Int]`, `split`/`join`, `replace`, string `+=`, indexing a built string and `json.parse` stay near-linear (`Map[String, Int]` at 1.6M keys 652 ms, 6.8x for 4x the keys from cache misses). `List.insert(0, x)` and `List.remove(0)` are O(n) memmoves, 10.7 s for 320k operations, as in Go and Rust; `Deque` is the queue.
- 108 MB, 2M-line word count (split, `Map[String, Int]`): 0.78 s in ms against 1.35 s for Go.

### 2026-11-12, reference fixes and `contains` on short strings

Revision `0d723018` plus this change, Release LLVM build, min of 5, shared 4 vCPU Xeon @ 2.10GHz, Go 1.24, rustc stable.

- The suite no longer built: `c05-calculator` still used `try`. Ported to postfix `?`.
- `c18-cron-next-runs` read 11.2 s against Rust's 0.75 s. Not a compiler regression: the Manuscript reference kept scanning all 3001 days after `count` runs were found, where the Rust and Go references stop at `count`. The reference now returns at `count` (785 ms, 1.07x Rust).
- `String.contains` with a one-byte needle in a string of at most 16 bytes (`"#.SE".contains(c)`) scans directly instead of going through `find`. `c16` under callgrind (600 KB input): 83.0M to 64.5M instructions; wall 112 to 104 ms.

| program | ms ms | go ms | rust ms | ms/go | ms/rust |
|---|---:|---:|---:|---:|---:|
| c03-csv-group-sum | 75.8 | 40.5 | 29.0 | 1.87x | 2.62x |
| c05-calculator | 71.7 | 49.0 | 131.3 | 1.46x | 0.55x |
| c09-ciphers | 48.3 | 53.1 | 36.0 | 0.91x | 1.34x |
| c13-inventory-orders | 265.2 | 259.5 | 141.6 | 1.02x | 1.87x |
| c14-dp-suite | 736.8 | 1404.7 | 452.8 | 0.52x | 1.63x |
| c16-maze-bfs | 104.2 | 37.5 | 30.4 | 2.77x | 3.42x |
| c18-cron-next-runs | 785.5 | 1016.5 | 731.6 | 0.77x | 1.07x |
| c25-log-analyzer | 29.7 | 54.1 | 21.2 | 0.55x | 1.40x |
| c36-bank-ledger | 110.4 | 110.8 | 61.7 | 1.00x | 1.79x |
| c44-unified-diff | 18.0 | 83.6 | 13.8 | 0.22x | 1.31x |

Remaining gaps, in order: `c16` (the Manuscript reference holds the grid as `List[List[String]]` of one-character strings, 16 bytes a cell and a `chars()` allocation per line, against Rust's `Vec<char>`; the rest of `contains` is about 40 instructions of inline-string decoding), `c03` (`split` and `find`), `c13`, `c36`, `c14`. `c44` is 3 ms in the 2026-11-07 table and 18 ms now; unexplained, to investigate.

Also in this change: scalar slicing of an inline (at most 16 byte) ASCII string took the walking path because only heap strings carry the ASCII flag; `known_ascii` now tests an inline string's bits. `c03` under callgrind (3 MB input): 1,074.8M to 1,045.8M instructions (-2.7%); wall time is inside the noise. The rest of `c03` is spread over `scalar_values().all(...)` list allocations, `split`, `replace` and map inserts; callgrind sends every allocation to glibc `malloc` (see the profiling note above), so allocator rows in these profiles are not the release costs.

### 2026-11-16, filter/map/sum chains over records fuse

`fuse.rs` fused `filter`/`map`/`sum` chains only over lists of numbers, so `orders.filter(fn o: o.status == "placed").map(fn o: o.total).sum()` over a `List[Order]` built a list of deep-cloned orders first. A stage now reads its element in place (a `filter` passes the borrowed element on, a `map` must produce a number), the chain must end in numbers, and a text literal without interpolation counts as a reading expression. Microbenchmark (2000 orders, 2000 chains, callgrind): 5.33G to 2.33G instructions. `c13-inventory-orders` min of 5, same machine and method as the section above: 274.9 to 243.7 ms (1.82x to 1.57x Rust). Other rows are within noise of the 2026-11-16 table. The rest of c13's gap is `orders.count(..)` over a freshly cloned `values()` where the checker does not lend, and the `get(..).clone()` round trip in `ship`/`cancel`.

### 2026-11-16, suite rebuilt on current main

Revision `3b2ef968`, Release LLVM build, min of 5, shared 4 vCPU Xeon @ 2.10GHz, Go 1.24, rustc stable. `c16-maze-bfs` stopped building (`chars` borrows the closure parameter, which the checker now rejects): the reference clones the list it builds.

| program | ms ms | go ms | rust ms | ms/go | ms/rust |
|---|---:|---:|---:|---:|---:|
| c03-csv-group-sum | 52.4 | 45.2 | 30.0 | 1.16x | 1.75x |
| c05-calculator | 44.5 | 59.9 | 126.6 | 0.74x | 0.35x |
| c09-ciphers | 50.0 | 57.6 | 38.3 | 0.87x | 1.31x |
| c13-inventory-orders | 274.9 | 310.7 | 150.8 | 0.88x | 1.82x |
| c14-dp-suite | 520.6 | 1594.4 | 453.1 | 0.33x | 1.15x |
| c16-maze-bfs | 82.8 | 35.0 | 33.3 | 2.36x | 2.49x |
| c18-cron-next-runs | 861.3 | 1144.3 | 822.7 | 0.75x | 1.05x |
| c25-log-analyzer | 23.1 | 55.1 | 21.6 | 0.42x | 1.07x |
| c36-bank-ledger | 76.1 | 129.7 | 64.3 | 0.59x | 1.18x |
| c44-unified-diff | 15.4 | 100.4 | 15.2 | 0.15x | 1.02x |

Against the 2026-11-12 table: c03 2.62x to 1.75x, c14 1.63x to 1.15x, c36 1.79x to 1.18x, c44 1.31x to 1.02x. Remaining gaps against Rust: c16 (grid held as `List[List[String]]`), c13 (map call counts), c03, c09.

### 2026-11-18, c16 reference holds the grid as `List[Int]` rows

Chinmay approved the change (Manuscript has no character type). `c16-maze-bfs/solutions/ms/main.ms.ref` now keeps scalar values (`line.scalar_values()`; `#` 35, `.` 46, `S` 83, `E` 69) instead of one-character strings. Output is identical on both generated inputs. Shared 4 vCPU VM, release build, same input as the rows above, CPU time (user+sys), median of 9 alternating runs; instructions from callgrind.

| Reference | CPU ms (median) | Instructions |
| --- | --- | --- |
| Manuscript, `List[List[String]]` cells | 81 | 345.7M |
| Manuscript, `List[List[Int]]` cells | 31 | 108.0M |
| Rust | 40 | n/a |

The Manuscript reference is now level with or slightly ahead of the Rust one, whose rows are `Vec<char>`. The earlier c16 gap was the 16-byte `String` cell, not code generation.

## datastructures

_Core collections against go and rust. Run: `make perf GROUP=datastructures`._

`sh bench/perf/datastructures/run.sh N` on a shared 4-CPU Linux VM (Intel Xeon @ 2.30GHz), Go 1.24, `rustc -O3`. Nanoseconds per operation, best of N; compare numbers only within one run, since this host varies by 10 to 20% between runs. Ratios below 1.00 mean Manuscript is faster.

The current runner rotates version order and requires successful producers, exact
operation counts, and every expected row in each trial before printing a table.
Go has no SortedMap row, so its timing and ratio are unavailable. Zero timings
remain visible but do not produce ratios. These checks validate measurement
accounting: the producers retain their existing nonzero-total observability
guards, but do not emit per-operation checksums to prove equivalent results.
The dated measurements below predate this accounting validation.

### 2026-11-23 (List.swap of plain elements in line)

Revision: this branch on top of `1d810acacb`, Release build of the C port, 4-CPU shared VM; callgrind on 100k `PriorityQueue[Int]` enqueues and 100k dequeues (`bench/perf/datastructures/ms/src/main.ms` shape).

| Measure | Before | After |
| --- | ---: | ---: |
| Instructions, 100k enqueue and dequeue | 240.0M | 72.8M |

`List.swap` called `msrt_list_swap` for every element, which went through the descriptor and three `memcpy` calls (104M plus 57M in libc of the 240M). For an element that owns nothing it is now two checked indices (the runtime's `List.swap` fault, unchanged) and two reads and two stores in line, like `set`; elements that own something still use the runtime. `sift_up` and `sift_down` swap on every level.

The string pipeline (`string_build_split_join_replace`, 144M against Rust's 71M instructions) is bound by calls the compiled code cannot inline: 800k `msrt_strbuilder_append` calls at 35 instructions plus a libc `memcpy` each, and about 95 instructions per match in `ms_needle_find` over two passes of `replace` (count, then fill). An inline copy of short strings and an inline compare in `find_short` measured within 1% of the libc calls, so neither is kept.

### 2026-11-23 (natives change a resource local in its closing slot)

Revision: this branch on top of `f783550`, Release build of the C port, 4-CPU shared VM; before is the section below, after the median of three runs of `ms run bench/perf/datastructures/ms/src/main.ms`. Callgrind on 1M `BytesBuilder.append` calls.

| Measure | Before | After |
| --- | ---: | ---: |
| Instructions, 1M `BytesBuilder.append` | 99M | 29M |
| bytes_append, ns/op | 10.7 | 1.2 |
| string_build_split_join_replace, ns/op | 72.4 | 42.4 |
| list_append, ns/op | 5.3 | 5.3 |
| map_int_put_get, ns/op | 61.7 | 56.8 |
| list_sort_cmp, ns/op | 232.1 | 243 |
| sorted_map_add_contains, ns/op | 170.3 | 159 |

A bodiless `var` method on a resource local (`bb.append(x)`) moved the value out of its closing slot into a stack slot, cancelled the slot's cleanup, called the native, then took the value back, registered the cleanup again and put it into the slot (about 70 of the 99 instructions). The native now gets the closing slot's address and changes the value there; the slot's own cleanup stays registered, so a fault inside the native still closes the value. Sort and map rows are within run-to-run noise.

### 2026-11-23 (C runtime: inline list push, inline scheduler lookup, cleanup stack reuse)

Revision: this branch on top of `17ecd65877`, Release build of the C port, 4-CPU shared VM; `ms run bench/perf/datastructures/ms/src/main.ms`, before from one run on main and after the median of three. Callgrind on 1M `BytesBuilder.append` calls.

| Measure | Before | After |
| --- | ---: | ---: |
| Instructions, 1M `BytesBuilder.append` | 213M | 99M |
| bytes_append, ns/op | 29.0 | 10.7 |
| string_build_split_join_replace, ns/op | 132.5 | 72.4 |
| map_int_put_get, ns/op | 80.4 | 61.7 |
| list_append, ns/op | 7.3 | 5.3 |
| list_sort_cmp, ns/op | 264.3 | 232.1 |
| sorted_map_add_contains, ns/op | 197.1 | 170.3 |

`ms_list_push` and `ms_list_extend` are inline: a list that owns a buffer with room takes no call and a constant element size becomes a plain store (the call and the `memcpy` were 85 of the 213 instructions per append). `ms_sched`, `ms_sched_if_any` and `ms_task_running` read the thread-local scheduler in line, which the cleanup, shield and guard calls each repeat. `ms_cleanup_cancel` of the innermost entry pops it instead of leaving a no-op entry, so a loop that cancels and registers a cleanup each pass keeps one slot (it grew 16 bytes per iteration until the loop ended). What remains per append is the cleanup registration the unwind pass wraps around every native that can fault.

### 2026-11-12 (Deque and Queue slot moves)

Revision: this branch on top of `b6717db6`; callgrind on 1M iterations of two `push_back` and one `pop_front` on a `Deque[Int]`, then a drain (3M pushes and pops).

| Measure | Before | After |
| --- | ---: | ---: |
| Instructions | 418M | 159M |

`List.replace` lowers to an in-line move-out and refill (`list.get` then `move.out` then `list.fill`, or `list.set` for an element that needs no drop) instead of a call to `msrt_list_replace`, so `pop_front`, `pop_back` and `Queue.dequeue` no longer leave the compiled code (68M runtime instructions and 110M in `pop_front` before). `Deque.grow` appended `null` slots and then rotated the ring with `List.rotate`, which swaps through `msrt_list_swap` (71M); it now moves only the run from `start` to the end once, with `replace` and `set`.

`List.prepend`, `insert` and `remove` on an owned list value lowered to `msrt_list_take`, `msrt_list_drop_n`, a list literal and two `msrt_list_concat` calls (three lists, every element copied twice); they now call `msrt_list_insert` and `msrt_list_remove` in place. 20,000 rounds of `remove(0)` and `prepend` on a 2,000-element `List[Int]`: 995M to 354M instructions, the rest being the tail shift itself.

`List.swap` of an element that needs no drop (a plain record, an optional scalar) is two loads and two stores in line like a scalar, not a call to `msrt_list_swap`: 1M swaps of a two-field record, 79.4M to 8.4M instructions. Elements that own heap data still swap through the runtime. Grid BFS plus priority queue, `bench/perf/structural-gaps/queues.ms` on `68b859e5`: 1,380M instructions against C's 603M; the priority queue's `sift_down` and `sift_up` are 71% of it, so the remaining gap is there, not in `Deque`.

### 2026-10-27 (PriorityQueue sift-down, second pass)

Revision: this branch on top of `b2a6f03f`; callgrind on 100k enqueue and dequeue, `run.sh 7` twice.

| Measure | Before | After | Rust |
| --- | ---: | ---: | ---: |
| Instructions, 100k enqueue and dequeue | 87.8M | 81.5M | 44.9M |
| ns/op (`run.sh 7`, two runs) | 93 to 98 | 90 to 96 | 77 to 79 |

`sift_down` loops while `0 <= at < size / 2` and tests `right < size` explicitly, so the left index is proven in range by the loop guard and the right by its own test; the separate last-level step is gone and the child choice is a branch instead of a select. Tried and dropped: one list of `{value, order}` entries (190M instructions, since swapping record elements goes through the runtime and a field cannot move out of an entry, so `dequeue` would also clone); clamping the loop to the shorter of `heap` and `orders` (86.4M, no real change). Without the `orders` swap the loop would be 71.6M, so the second list costs about 16M. What remains is a compiler matter: the range analysis does not tie `orders`' length to `heap`'s, and `peek` clones because it returns an owned `Optional[T]`.

### 2026-10-27 (Bytes append and SortedMap re-measure)

Revision: this branch on top of `main` after #1692 (`buildmove`); `run.sh 7` twice, plus callgrind and `getrusage` on the standalone 4M-byte append and 300k-key SortedMap programs.

| Operation | Manuscript | Rust | Ratio |
| --- | ---: | ---: | ---: |
| Bytes append (ns/byte, two runs) | 0.9 to 1.0 | 0.9 | 1.00 to 1.12 (was 1.39 to 1.55) |
| Bytes append, page faults (4M bytes) | 1053 | 1087 | 0.97 (was 2033 vs 1086) |
| SortedMap add and contains (ns/op, `run.sh`) | 191 to 199 | 207 to 217 | 0.92 |
| SortedMap add and contains, 300k keys, process min of 15 | 127 ms | 121 ms | 1.05 |
| SortedMap instructions, 300k keys | 328M | 252M | 1.30 |

Bytes: the earlier gap was the copy `build()` made of the whole buffer, which doubled page faults; `buildmove` moves the buffer for a builder that is not built again, so faults are at Rust's level. The append loop itself is still 13 against 8 instructions per byte (the sealed-flag test and the length write-back each iteration); wall time is within noise of Rust. SortedMap: wall time is at parity, with more instructions than `BTreeMap` that the cache misses hide.

### 2026-10-27 (PriorityQueue sift-down guards)

Revision: this branch on top of `9f41921f`; callgrind on 100k enqueue and dequeue, plus `run.sh 7` twice on the same host.

| Measure | Before | After | Rust |
| --- | ---: | ---: | ---: |
| Instructions, 100k enqueue and dequeue | 110.7M | 87.4M | 44.9M |
| ns/op (`run.sh 7`, two runs) | 112 | 97 to 100 | 81 to 97 |

`sift_down` now loops while `0 <= at < (size - 1) / 2`, so the range analysis proves the child indices non-negative and in range and drops their normalization and bounds checks (75 to 52 instructions per level); the one-child last level is handled after the loop. Without the explicit `at >= 0` guard the analysis lost the lower bound of `at` and kept the checks. What remains: the `orders` list is a separate list whose length the analysis does not tie to `heap`, and the comparator's checked subtraction.

### 2026-10-27 (SortedMap)

Revision: this branch on top of `d370bb89`; best of 10 runs of the `sorted_map_add_contains` row, same machine class.

| Operation | Manuscript before | Manuscript after | Rust |
| --- | ---: | ---: | ---: |
| SortedMap add and contains | 214 | 193 | 169 |

Chunks now split at 128 entries instead of 256. Split by operation at 300k keys: add 290 to 255 ns, contains unchanged at 138 ns, which already beats `BTreeMap` (157). The remaining gap is all in add: callgrind shows 58% of data-cache read misses inside `memmove` shifting chunk tails and the chunk-header lists. A three-level layout (segments of chunks, as a struct or as nested lists) made both add and contains slower and was dropped. As a struct list it first hit #1661 (a `var def` on a list element deep-copied it, 4 µs per add), fixed in the same change; retried after the fix it is still slower (add 317 vs 298 ns, contains 164 vs 137 ns at 300k keys, chunks of 64 or 128 and 32 or 64 chunks per segment), so the top-level shifts are not the cost. A B-tree written in Manuscript (nodes holding keys, values and children inline, split on the way down; 15 to 127 keys per node) was also slower: add 334 to 471 ns and contains 198 to 279 ns against 291 and 135 for the chunked layout in the same run, so it was not kept.

### 2026-10-27

Revision: this branch on top of `90e401c46`; same machine class, one `run.sh 5` before and after.

| Operation | Manuscript before | Manuscript after | Rust |
| --- | ---: | ---: | ---: |
| PriorityQueue enqueue and dequeue | 210 | 103 | 93 |

The 2026-10-26 heap moved entries with `List.swap`, which for every element type was a call into the runtime (about 55 instructions per swap, 63% of the benchmark). Swapping scalar elements is now two inline loads and two stores, and the heap sifts down to the bottom along the earlier child before sifting back up (callgrind: 317M to 111M instructions for 100k enqueue and dequeue). `fs.stat` did not regress against `c1b81215` on this host.

### 2026-10-26

Revision: this branch on top of `2e1227ae`; five rounds of `run.sh`, ranges across the last runs.

| Operation | Manuscript | Go | Rust | vs Rust |
| --- | ---: | ---: | ---: | ---: |
| list append | 2.7–3.5 | 34–41 | 3.3–3.8 | 0.8–0.9 |
| list get (random) | 2.4–2.7 | 6.7–7.7 | 4.1–5.4 | 0.5–0.65 |
| list sort (Int) | 16.9–17.4 | 323–338 | 30–31 | 0.55 |
| list sort (record comparator) | 55–56 | 1236–1305 | 45–46 | 1.2 (was 1.4) |
| Map[Int, Int] put and get | 34–35 | 71–74 | 72–73 | 0.48 |
| Map[String, Int] put and get | 38 | 58 | 87–92 | 0.42 |
| Set[Int] add and contains | 41–42 | 68–72 | 54–55 | 0.75–0.8 |
| String build, split, join, replace | 27–28 | 58–62 | 23–24 | 1.15–1.25 (was 2.04) |
| Bytes append | 1.1–1.8 | 3–3.5 | 0.7–0.8 | 1.4–2.4 |
| PriorityQueue enqueue and dequeue | 74–75 | 183–185 | 62–63 | 1.2 |
| SortedMap add and contains | 190 | – | 149–151 | 1.26 |

What bounds the remaining gaps (callgrind, instruction counts):

- PriorityQueue: the comparator closure is inlined and the heap is one list of entries whose accesses the range analysis proves (69.2M to 49.7M instructions for 100k enqueue and dequeue, 26 instructions per heap level). Go and Rust heaps here carry the same enqueue number as a tie-break, since `PriorityQueue` is FIFO among equal priorities; without it Rust's heap is 37 ns/op, which is a different contract. What remains is the dependent load-compare chain down the heap.
- Record sort by comparator: generated stable merge sort (halves sorted into alternating lists, so no copy per level) against Rust's driftsort.
- Bytes append: 12 instructions per byte, fully inlined; wall time here is dominated by page faults on the growing buffer.
- String pipeline: split, join and replace are one pass each with exact-size results; the rest is the substring search itself.
- SortedMap: random keys over a chunked array; cache misses dominate.

### 2026-11-03, refcount removal

`632c42ba` (refcounts) against `d6052382` (no refcounts), min of 5 rotating trials: `bytes_append` 1.6 to 1.1 ns (0.69x), `list_sort_int` 0.89x, `string_build_split_join_replace` 1.12x, the rest within 5%. Table in [refcount-removal-2026-11-03.md](../refcount-removal-2026-11-03.md).

## json

_Json parse and stringify against node. Run: `make perf GROUP=json`._

`@std/json` `parse` and `stringify` against Node's `JSON.parse` and `JSON.stringify` on the standard documents (`twitter.json`, `canada.json`, `citm_catalog.json`) and a small RPC message. Both sides warm up, then take the median of at least five runs over one second. Throughput is MB of document per second; the last column is Node time over Manuscript time, so above 1.00x Manuscript is faster. Reproduce with `sh bench/perf/json/run.sh` (needs `node`); compare only runs from one machine.

### main at c1b81215 (2026-10-25)

linux/amd64, four cores, Node v22.22.0, `ms` Release build (LLVM).

| document | operation | Node MB/s | Manuscript MB/s | Manuscript speed |
|---|---|---:|---:|---:|
| small | parse | 190 | 230 | 1.21x |
| small | stringify | 299 | 352 | 1.18x |
| twitter | parse | 569 | 770 | 1.35x |
| twitter | stringify | 364 | 1266 | 3.48x |
| canada | parse | 162 | 419 | 2.58x |
| canada | stringify | 128 | 355 | 2.78x |
| citm_catalog | parse | 671 | 904 | 1.35x |
| citm_catalog | stringify | 908 | 1269 | 1.40x |

Manuscript is ahead of V8 on every row here, and three further runs on the same machine the same day agreed within a few percent (twitter parse 1.29-1.32x, citm stringify 1.41-1.49x). A run on another machine by the JsonValue thread the same day measured twitter parse at 0.94x and citm stringify at 0.88x, so across hardware the range is about 0.9-3.4x; rerun on your own machine before citing a row. `parse` builds a `JsonValue` tree, the same work `JSON.parse` does for a JavaScript value; typed `parse[T]` into records is a separate path and is not measured here.

### History

| Change | twitter parse | canada parse | citm parse | PR |
|---|---:|---:|---:|---|
| Before the compact document arena | 0.24-1.0x on every row | | | |
| Compact document arena, SWAR scans, moved results | 0.60x | 2.4x | 0.75x | #1203 |
| Runtime builds the tree while scanning; SSE2 scans | 1.0-1.3x | 2.2x | 0.85-1.0x | #1209 |
| Exactly sized reserved maps | 1.05-1.08x | 2.0-2.5x | 1.13-1.44x | #1210 |
| Bulk object fill, cheaper tree drop | 1.13-1.16x | 2.0-2.3x | 1.2-1.5x | #1212 |

### 2026-10-27: against serde_json, and the writer

linux/amd64, four shared cores (a slower machine than the table above; compare only within this section), Node v22.22.0. serde_json 1.x `Value` (`from_slice`, `to_vec`, release) measured in the same process protocol: warm-up, then the median of at least five runs over one second.

| document | operation | serde_json MB/s | Manuscript before | Manuscript after |
|---|---|---:|---:|---:|
| twitter | parse | 137 | 465 | 451 |
| twitter | stringify | 827 | 584 | 687 |
| canada | stringify | 425 | 267 | 321 |
| citm_catalog | stringify | 914 | 544 | 689 |

Parse into a tree is about 3x serde_json's `Value`. Stringify was 1.4-1.7x behind; `number_text_valid` built a `Scanner` (and a `Doc`) for every number it wrote, and `Writer::quoted` paid a boundary check and a second scan per string. Validating numbers on the bytes and taking a single-copy path for strings with nothing to escape gives +18% to +27%. What remains is `Writer` call overhead per node (about 30 instructions per node in the generated walker plus the runtime call) and buffer growth.

### 2026-10-27: serde_json harness, writer without revalidation (9f41921f + this change)

linux/amd64, four shared cores, Node v22.22.0, serde_json 1.x `Value` (`bench/perf/json/rust`: `from_slice`, `to_vec`, release). `sh bench/perf/json/run.sh`; MB/s is document size over time, so compare columns within a row. Callgrind counts are `ms ... quick <doc>:stringify` totals (one parse, one tree copy and six stringify runs).

| document | operation | serde_json MB/s | Manuscript before | Manuscript after | after / serde_json |
|---|---|---:|---:|---:|---:|
| small | stringify | 593 | 384 | 393 | 0.66x |
| twitter | stringify | 1420 | 693 | 933 | 0.66x |
| citm_catalog | stringify | 2461 | 1508 | 1514 | 0.62x |
| canada | stringify | 681 | 598 | 608 | 0.89x |
| twitter | parse | 190 | 669 | 707 | 3.7x |
| citm_catalog | parse | 365 | 873 | 850 | 2.3x |

`Writer::finish` validated the whole output as UTF-8 again (12% of twitter stringify instructions) though only whole `&str`s and ASCII are appended; it now hands the buffer over unchecked. Strings under 24 bytes took a byte-at-a-time table walk; the vector scan with its word tail is cheaper at every length measured (twitter 70.96M → 57.59M instructions, citm 132.6M → 126.3M).

Typed stringify of a tree is still 0.62-0.89x serde_json on this machine, so the gap in #1680 is narrowed, not closed: what remains is spread over the generated walker (`json_encode`, ~15% on citm), key and separator bookkeeping and per-value runtime calls.

### 2026-10-27: short names, strings and numbers in one write

linux/amd64, four shared cores, Node v22.22.0, serde_json 1.x. Three runs of `sh bench/perf/json/run.sh`; ranges are the three MB/s values per row. `records` is new: 10,000 typed rows (`id`, `name`, `tags`, `score`, `ok`) written without a `JsonValue`, against serde_json's derived `Serialize` over `Vec<Row>` and Node's `JSON.stringify` of the same objects.

| document | serde_json MB/s | Manuscript before | Manuscript after | after / serde_json |
|---|---:|---:|---:|---:|
| small | 565-624 | 384-393 | 519-549 | 0.86-0.92x |
| twitter | 1453-1585 | 683-693 | 1037-1153 | 0.70-0.79x |
| canada | 651-678 | 598-608 | 640-671 | 0.96-1.03x |
| citm_catalog | 2483-2545 | 1508-1514 | 1736-1781 | 0.69-0.70x |
| records | 738-793 | not measured | 626-666 | 0.80-0.87x |

"Before" is the table above (main at 9f41921f, same machine class, so compare within a row only). Callgrind instructions for the stringify walker on citm (`ms build` then `valgrind --tool=callgrind --toggle-collect='*json_encode*' jb quick citm_catalog:stringify`, one warm-up and five runs): 77.4M → 61.1M.

What changed, all in `Writer` and `ms_rt::scan`:

- A name or string of at most 16 bytes with nothing to escape is checked with two overlapping word tests and written, quotes and colon included, after one capacity check (`push_member_name`, `push_member_quoted`, `push_string_short`). Names were about 190 instructions each in the walker; most of that was bookkeeping around three capacity checks and a byte loop.
- Number text of 1-16 digits with no sign, point or leading zero skips the number grammar (`json_plain_digits`); every other number still goes through `scan_number`.
- The short checks load through raw pointers inside `ms-rt`, which allows `unsafe`; `ms-std-json` still has none.

Remaining profile on `records`: float formatting (~16%, about 300 instructions per float against serde's ~150), the call chain from generated code into `Writer` (wrapper plus method per node), and buffer growth copies. Typed `records` and tree stringify are still below serde_json except on canada, so #1680 stays open.

### 2026-10-27: floats with a short fraction

linux/amd64, four shared cores, Node v22.22.0, serde_json 1.x; three runs of `sh bench/perf/json/run.sh` on main with this change (it includes other changes merged since the section above, so only the last column is the comparison to read).

| document | serde_json MB/s | Manuscript MB/s | Manuscript / serde_json |
|---|---:|---:|---:|
| small | 569-601 | 548-577 | 0.91-1.01x |
| twitter | 1425-1495 | 1575-1640 | 1.05-1.15x |
| canada | 622-656 | 688-767 | 1.09-1.23x |
| citm_catalog | 2454-2639 | 1783-1832 | 0.68-0.73x |
| records | 770-811 | 720-756 | 0.93-0.94x |

A float that is a decimal of one to four fraction digits (`1234.5`, `0.25`, `99.99`) is scaled to an integer, checked by dividing back, and written two digits at a time with the point placed by position; the check yields the same digits as the shortest-round-trip formatter because the quotient of an exact integer by an exact power of ten is the correctly rounded double. `Writer::float` on `i + 0.5` went from about 218 to 135 instructions. The test `plain_decimals_print_as_rust_displays_them` compares 800,000 values in 1e-3..1e11 against Rust's `{}` byte for byte.

citm_catalog is the remaining gap: its time is in the generated `JsonValue` walker and the per-node calls into `Writer`, not in escaping or numbers.

### 2026-10-27: native tree walker and decimal validation

linux/amd64, four shared cores (noisy: two back-to-back runs differed by up to 25% on canada), Node v22.22.0, serde_json 1.x; `sh bench/perf/json/run.sh` on this branch.

| document | serde_json MB/s | Manuscript MB/s | Manuscript / serde_json |
|---|---:|---:|---:|
| small | 586 | 551 | 0.94x |
| twitter | 1400-1500 | 1627-1659 | 1.11-1.16x |
| canada | 654-657 | 471-640 | 0.72-0.98x |
| citm_catalog | 2219-2451 | 2178-2313 | 0.89-1.04x |
| records | 786 | 750 | 0.95x |

Tree stringify (`JsonValue`) no longer calls `Writer` once per node from generated code. The compiler emits one view thunk per type (`value -> kind, payload`), and `msrt_json_w_tree` walks the tree natively through `ms_rt::tree::walk` into the same `Writer`. citm walker instructions: 61.1M → 52.8M. Number text of up to 32 simple decimal bytes (`-?digits(.digits)?`, no leading zero) is validated with word tests (`json_simple_number`) instead of `scan_number`; canada callgrind total is 378M instructions.

canada and citm remain within noise of serde_json rather than clearly above it, so #1680 stays open.

### 2026-10-27: 17-32 byte numbers and fractions

linux/amd64, four shared cores (noisy: wall ratios swing ±15% between runs, so medians of repeated `sh bench/perf/json/run.sh` runs), Node v22.22.0, serde_json 1.x.

| document | serde_json MB/s | Manuscript / serde_json (median of rounds) | range |
|---|---:|---:|---|
| small | 580 | 0.96x | 0.93-1.02x |
| twitter | 1450 | 1.14x | 1.11-1.25x |
| canada | 650 | 1.27x | 1.11-1.73x |
| citm_catalog | 2400 | 0.91x | 0.64-1.36x |
| records | 780 | 0.92x | 0.89-1.26x |

canada's numbers are 17-19 bytes (`-65.613616999999977`), which missed both the 16-byte copy and the byte tail of the decimal check. `push_short` now copies up to 32 bytes with two overlapping 16-byte moves, and the fraction check tests whole words plus one word overlapping the end (`all_digits`). canada tree stringify went from about 0.98x to about 1.27x; `Writer::number` callgrind instructions fell 105M → 76M.

serde_json's own callgrind cost for one `to_vec` of the tree (`valgrind --toggle-collect='*enc*'`, six calls): citm 53.7M, canada 96.8M, twitter 24.5M. Manuscript's citm walker is about 8% more instructions per stringify than serde_json's, matching the 0.91x wall ratio; the cost is spread over the walker (~50 instructions a node), `Writer::key` (~95 a key) and `close`. Inlining `Writer` methods into the walker did not reduce it.

### 2026-10-27: one dispatch per node in tree stringify

Platform benchmarks workflow, three rounds per platform (`.github/workflows/bench-platforms.yml`, before this change: linux-amd64 median ms/serde_json: small 0.87x, twitter 1.22x, canada 1.37x, citm_catalog 0.75x, records 0.91x). callgrind `--branch-sim=yes` on the citm tree walk showed why citm trailed while instruction counts matched serde_json's (51M against 54M for six calls): Manuscript took 560k branch mispredicts to serde_json's 374k, 342k of them indirect jumps. Each node went through two jump tables, the compiler's view thunk (on the case) and the runtime loop (on the kind the thunk returned).

The view thunk now calls the writer natives itself (`msrt_json_w_null/bool/number/string`, `msrt_json_tree_array/object` for containers), and the runtime loop only advances through the open containers. Indirect mispredicts fell 342k → 206k and the total to 421k; the remaining one is the thunk's switch on the case, which depends on the data.

Local runs (four shared cores, medians of four rounds, ms / serde_json): citm_catalog 0.95x (was 0.91x), small 0.99x (0.96x), records 0.94x (0.92x), twitter 1.20x (1.14x).

## web

_Http server against go. Run: `make perf GROUP=web`._

`sh bench/perf/web/run.sh 5` on a shared 4-CPU Linux VM, server on 2 CPUs, load on the other 2, Go 1.24.7 (`CGO_ENABLED=0`). Ranges cover both rounds of a run. Compare numbers only within one run: this host varies by 10 to 15% between runs.

| Measurement | Manuscript | Go |
| --- | ---: | ---: |
| `/health` req/s | 75.7k–81.9k | 54.8k–55.2k |
| `/user/42` req/s | 70.2k–75.3k | 52.1k–54.5k |
| `/top?n=10` req/s | 20.2k–20.4k | 23.6k–26.2k |
| `/health` p99 | 2.9–4.3 ms | 5.6–5.8 ms |
| `/io` req/s | 253–279 | 624–690 |
| `/health` req/s during `/io` | 773 | 2,538 |
| `/health` p99 during `/io` | 137 ms | 69 ms |
| Threads | 2 | 67 |
| Resident memory after load | 9.7 MB | 15 MB |
| System calls in 5 idle seconds | 0 | 1 |
| System calls per `/health` request | 2.07 | 2.73 |
| Resident memory, 10,000 idle connections | 31 MB | 197 MB |
| `/health` req/s beside 10,000 idle connections | 38.9k | 56.8k |

Where Manuscript is behind: file and DNS calls block the runtime thread, so `/io` and everything beside it wait on the disk, and `/health` slows beside many idle connections.

### 2026-11-23 (live-byte accounting only where it is read)

Revision: `4fc7255da7` plus this change, Release build of the C port; callgrind on the server (`ms/`, one worker) answering `/health` from the C load generator, instructions per request counted from `ms_http_target_parse` calls (startup included, about 100M).

| Measure | Before | After |
| --- | ---: | ---: |
| Instructions per `/health` request | 27.7k | 24.9k |
| `mi_usable_size` share of all instructions | 8.1% | 0% |

`ms_alloc`, `ms_realloc` and `ms_free` each called `mi_usable_size` to keep the live-byte count that `process.memory_usage().heap_used` reads. The count now starts before `main` only in a program that links `process_memory.c` (the unit holding `msstd_process_memory_usage`), so a program that never asks pays nothing; one that does gets the same figure as before, minus blocks made before `main`. Throughput on one CPU is within the 15% run-to-run noise of this VM (median of 9 alternating runs 71k before and after the earlier allocation experiment); the server is at 12.5 µs per request, of which a thread handoff is about 1.2 µs and a heap accounting call pair was about 0.3 µs.

### 2026-11-24 (request path: date cache, content-type gate, byte-builder start size)

Callgrind on the release server (one worker, `/health` from `loadc`, 16 connections), instructions per request as (total minus 6M startup) over requests served.

| Step | Instructions per `/health` request |
| --- | ---: |
| After live-bytes opt-in (2026-11-23) | 24.65k |
| `Date` formatted once a second per thread, not per response | 22.92k |
| Content-type sniff skips the HTML and XML probes unless the first non-space byte is `<`, and tests each signature's first byte before the masked compare | 22.25k |
| Byte builders start at 32 bytes, not 4 (allocations per request 42.4 to 39.5) | 21.95k |

A further step: received header fields are canonicalised into a stack buffer and the token test is a table, not a builder push and a substring search per byte, and the copy `exchange.headers()` makes reserves its lists: 21.95k to 21.62k (the `Host`-only load of `loadc`).

Throughput on this 4-CPU VM, `multicpu.sh`, 4 s rows, two rounds (req/s, rounds side by side), server on N CPUs and the load generator on the others:

| Path, CPUs | Manuscript | C | hyper |
| --- | ---: | ---: | ---: |
| `/health`, 1 | 73k, 83k | 175k, 180k | 120k, 121k |
| `/health`, 2 | 108k, 112k | 394k, 478k | 233k, 218k |
| `/health`, 4 shared | 108k, 104k | 406k, 401k | 261k, 245k |
| `/user/42`, 1 | 73k, 74k | 186k, 195k | 125k, 123k |
| `/user/42`, 2 | 109k, 98k | 393k, 382k | 219k, 225k |
| `/user/42`, 4 shared | 115k, 110k | 437k, 413k | 262k, 264k |

On one CPU Manuscript serves about 62% of hyper's rate, and the gap grows with CPUs (about 45% at two and four): 22k instructions a request explains the one-CPU gap, but the second CPU adds only 1.4x where hyper adds 1.9x, which points at the handoff between the libuv loop thread and the scheduler threads, not at the request path.

The remaining top self costs per request are list growth (1.1k), `memcpy` (0.8k), allocation (0.7k), the task switch (0.6k), llhttp (0.6k), and `exchange.headers()` copying the received headers (0.5k, in the frozen stdlib wrapper).

### 2026-11-24 (the server uses every thread it was given; writes leave the loop thread)

Two findings from per-thread CPU time (`/proc/<pid>/task/*/stat`) with the server on 2 CPUs:
- With `cores: 2` both worker promises of `serve` ran on the main thread. A thread started by an earlier wake had not registered when `ms_workers_spread_pick` scored the isolates, so the second pick saw one thread and chose it again; the second thread stayed idle. The pick now waits for every started thread to register.
- The single network loop thread was 98% busy at 108k requests a second: a send on loopback costs about 7 µs because the peer's receive work runs inside the `write`, and every send ran there. A write on a plain TCP connection now goes straight to the socket from the calling thread (`uv_try_write`) when no write operation is queued and more than one scheduler thread runs; otherwise, and for what the kernel does not take, it uses the loop as before. The loop thread waits for threads inside such a call before it closes the handle.

`multicpu.sh`-style rows, `/health`, `loadc` with 128 connections on the other CPUs, two runs each (req/s):

| Server CPUs | Before | Placement fix and direct write | hyper (same VM, earlier run) |
| --- | ---: | ---: | ---: |
| 1 | 66k, 78k | 71k, 76k | 120k |
| 2 | 114k, 118k | 100k, 104k | 218k to 233k |
| 4, load shared | 89k, 101k | 141k, 162k | 245k to 261k |

With one scheduler thread the direct write is slower (70k against 54k at one CPU: the loop thread's send overlaps the thread's other work), so it is off there. At two CPUs both threads now work but the loop thread still carries every read and the epoll, so the gain waits on moving reads off it.

### History

| Change | `/health` req/s | System calls per request | Idle system calls in 5 s |
| --- | ---: | ---: | ---: |
| Baseline (`b69b5b65`; Go 52k–61k in the same run) | 38.8k–51.0k | 8.4 | 392–487 |
| Sockets registered once, reactor parks until real work | 75.7k–81.9k | 2.07 | 0 |

### 2026-10-25

`sh bench/perf/web/run.sh 5` on main at `6003f16b`, shared 4-CPU Linux VM, server on 2 CPUs, load on the other 2, Go 1.24.7. Ranges cover both rounds. Whole-file reads and writes already run on the blocking pool on Unix (`ms-std-fs/src/ops.rs`), which the first table above predates; this run records the effect.

| Measurement | Manuscript | Go |
| --- | ---: | ---: |
| `/health` req/s | 81.5k–92.4k | 61.4k–62.4k |
| `/user/42` req/s | 80.0k–85.4k | 57.1k–59.6k |
| `/top?n=10` req/s | 20.4k–22.4k | 26.3k–27.9k |
| `/health` p99 | 2.5 ms | 5.2–5.3 ms |
| `/io` req/s | 490–546 | 707–728 |
| `/health` req/s during `/io` | 24.0k | 2.0k |
| `/health` p99 during `/io` | 12.6 ms | 97 ms |
| Threads | 6 | 68 |
| Resident memory after load | 70 MB | 15 MB |
| System calls in 5 idle seconds | 2 | 72 |
| System calls per `/health` request | 2.08 | 2.65 |
| Resident memory, 10,000 idle connections | 93 MB | 197 MB |
| `/health` req/s beside 10,000 idle connections | 75.2k | 63.9k |

`/health` beside `/io` improved from 773 to 24.0k req/s and its p99 from 137 ms to 12.6 ms. Resident memory after load rose from 9.7 MB to 70 MB (the `/io` payloads and pool threads); not investigated. Windows is measured by CI only: the whole-file offload now compiles there too, but this suite has not run on it.

### 2026-10-25, one task per request

`/health`, `/user/42` and `/top?n=10`, 64 connections, 4 s, server on CPUs 0 and 1, load on 2 and 3, shared 4-CPU Linux VM (±10% between runs). Runs of main (`7439d30d`) and this change alternated, three rounds each. Each request now runs as a task of the server's scope instead of inline on the reactor task (`design/proposals/http-server-request-tasks.md`).

| Build | `/health` req/s | `/user/42` req/s | `/top?n=10` req/s |
| --- | ---: | ---: | ---: |
| main, inline handlers | 102k–115k | 100k–113k | 23k–25k |
| task per request, stack pool 512 | 95k–111k | 85k–106k | 23k–24k |
| task per request, stack pool 32 (spike) | 32k–33k | 32k–33k | 15k–17k |

The pool of 32 stacks overflows on each reactor batch (up to 64 requests spawn before any runs), so every request paid `mmap`, `mprotect` and two `munmap` calls. With 512 the cost left is about 7% on the shortest handlers (`/health` median 107k against 114k).

### 2026-10-26, large-block reuse and inline file calls

`sh bench/perf/web/run.sh 3` before and after this change, shared 4-CPU Linux VM (±10% between runs). Zeroed large buffers (`vec![0; n]`) bypassed the runtime's block cache and faulted in fresh pages on every file read, blocking-pool jobs mapped a new block for every large result, and a single-task program still sent each file call through the pool.

| Measurement | before | after |
| --- | ---: | ---: |
| `/io` req/s | 863–944 | 1,232–1,265 |
| `/health` req/s during `/io` | 46.4k | 75.5k |
| Resident memory after load | 70.9 MB | 54.5 MB |
| `/health` req/s | 122.5k–123.7k | 108.5k–109.7k |

`/health` is within the run-to-run noise of this host; Go measured 105k–106k in the first run.

### 2026-10-26, fetch client

`sh bench/perf/web/fetch.sh 2`: Manuscript's `fetch` (one `Fetcher`, N tasks) and Go's `net/http` client against one Go file server on CPUs 0-1, clients on CPUs 2-3, shared 4-CPU Linux VM (+/-10% between runs). The Manuscript runtime uses one thread, Go's client two cores.

| Body, connections | Go req/s | Manuscript req/s |
| --- | ---: | ---: |
| 3 bytes, 1 | 4.2k | 6.6k |
| 3 bytes, 8 | 24.7k | 32.6k |
| 3 bytes, 64 | 30.0k | 38.0k |
| 8 MiB, 1 | 147 | 117 |
| 8 MiB, 8 | 221 | 90 |

Before this change an 8 MiB fetch ran at 40-81 req/s on one connection (seven memory-copy passes per body byte; now three). Callgrind over 20 fetches of 8 MiB: 1.18G to 0.52G instructions. `/io` (whole-file read and write) went from 676 to 756 req/s, with `/health` beside it from 26k to 40k req/s and its p99 from 11 to 5.8 ms: reads per request 40 to 5, writes 19 to 4. A 30-route router served 41k-46k requests per second before it stopped cloning its routes on each request, and 80k-83k after.

### 2026-10-26, fetch bodies received in place

`ResponseBody.read_all()` receives a fixed-length HTTP/1 body straight into the result buffer, and `fetch` uses it. `sh bench/perf/web/fetch.sh` style run, 8 MiB body, client on CPUs 2-3, three rounds on the shared VM (+/-10%):

| Connections | Go req/s | Manuscript before | Manuscript after |
| --- | ---: | ---: | ---: |
| 1 | 158-207 | 120-136 | 138-146 |
| 8 | 255-365 | 104-126 | 150-155 |

User CPU for 3 s at 8 connections: 1.47 s before, 0.12 s after (the rest is kernel receive and page faults). The Manuscript client still runs on one core, Go's on two.

### 2026-10-26, server on several cores

`server <port> <dir> <threads>` starts that many workers, each running `serve` with `HttpServerOptions(shared: True)` on one shared listener. Server on CPUs 0-1, 64 keep-alive connections from CPUs 2-3, 4 s per row, shared 4-CPU Linux VM (+/-10% between runs); two runs each.

| Server | `/top?n=10` req/s | `/health` req/s |
| --- | ---: | ---: |
| Go `net/http` | 34.4k, 37.5k | 85.1k, 84.6k |
| Manuscript, 1 thread | 26.3k, 25.1k | 118.3k, 105.7k |
| Manuscript, 2 workers | 58.1k, 56.9k | 140.7k, 136.1k |
| Manuscript, 4 workers (2 CPUs) | 59.1k, 61.4k | 150.7k, 139.9k |

A first run of this table had 2 workers at 38.6k/39.1k on `/top` and 65-72k on `/health`, below one thread: Rust code in a worker allocated through musl's `malloc`, which has one process-wide lock, and a `futex` trace showed the two workers handing that lock back and forth. Workers now allocate small Rust blocks from a process-wide heap that is never unmapped, with per-thread free lists (`worker_heap` in `ms-rt/src/alloc.rs`).

### 2026-10-26, fetch on several cores

`fetch.sh` gained a row that spreads the 8 connections over 2 worker threads (`ms/fetch <url> 8 <secs> 2`), one `Fetcher` task group per worker. Same machine and pinning as above (clients on CPUs 2-3), 3 s, two runs.

| 8 MiB body, 8 connections | req/s |
| --- | ---: |
| Go `net/http` | 424, 437 |
| Manuscript, tasks on one thread | 165, 151 |
| Manuscript, 2 worker threads | 371, 374 |

Worker threads needed the large-block reuse in `ms-rt/alloc.rs`: before it, one worker fetched 70-84 req/s against 190-198 on the main thread, because each body buffer was mapped and faulted in again.

### 2026-10-26, fetch on several cores after in-place bodies (#1503)

`sh bench/perf/web/fetch.sh 3`, tree with #1495 and #1503, same machine and pinning (server CPUs 0-1, clients CPUs 2-3), two runs.

| Body, connections | Go req/s | Manuscript, tasks on one thread | Manuscript, 2 worker threads |
| --- | ---: | ---: | ---: |
| 3 bytes, 8 | 38.8k, 39.9k | 53.7k, 54.9k | 49.8k, 45.7k |
| 8 MiB, 1 | 268, 242 | 260, 252 | |
| 8 MiB, 8 | 425, 363 | 237, 202 | 590, 479 |

With the body received in place, two worker threads put the 8 MiB case 35-39% above Go's client on the same two CPUs. For tiny bodies the extra thread costs 7-15%, so keep one thread there.

### 2026-10-27, fetch framings and worker cost

`sh bench/perf/web/fetch.sh 3` on main at `946c4f4` plus this change, shared 4-CPU Linux VM (server on CPUs 0 and 1, client on 2 and 3), Go 1.24.7. Compare only within this run (±10%).

| Case (1 connection unless noted) | Manuscript req/s | Go req/s |
| --- | ---: | ---: |
| 8 MiB, Content-Length | 218 | 252 |
| 8 MiB, chunked | 110 | 167 |
| 8 MiB text, gzip | 90 | 578 |
| tiny, 8 connections | 46.1k | 47.3k |
| tiny, 8 connections, 2 worker threads | 45.2k | |
| tiny, 8 connections, client pinned to 1 CPU | 48.5k | 38.4k |
| tiny, 8 connections, 2 worker threads, client pinned to 1 CPU | 46.2k | |
| 8 MiB, 8 connections | 245 | 379 |
| 8 MiB, 8 connections, 2 worker threads | 570 | |

Chunked bodies (#1538): the decoder now receives a chunk's data straight into the result, as fixed-length bodies already did, and decodes framing straight into it. Client CPU for chunked 8 MiB reads fell from 0.45 s to 0.32 s of user time per 400 requests (`time`, client on CPUs 2 and 3). Throughput did not move because the Go server and the kernel copies bound it (sys time is 2.0 s of the 4 s run). gzip is bound by inflate, 6.9 ms of user time per 8 MiB (miniz_oxide); the extra copies are not what costs there, so a faster inflate backend is the remaining lever.

Worker threads on tiny bodies (#1539): with free cores, two threads match or beat one (45k to 63k req/s across runs, within noise of the single-thread number) at about 20% more CPU per request. Pinned to one CPU, two threads are 8 to 10% slower (46.6k against 51.8k in a separate three-round check), the 7 to 15% the issue saw: the cost is two threads time-sharing a core, not per-request work. `strace -c` shows the same system calls per request on one thread and on two, and each isolate has its own lock-free arena, so no shared structure showed up as the fixed cost. Crossover: use worker threads when there are at least as many free cores as threads; tiny bodies gain nothing from them, 8 MiB bodies gain 2.3x with two threads.

### 2026-10-27: Rust baseline, equal cores

`sh bench/perf/web/run.sh 4` on `90e401c4`, shared 4-CPU Linux VM, servers on 2 CPUs, load on the other 2. The earlier tables ran Manuscript on one worker against servers using both cores, which understated it by about 2x. Manuscript now runs two workers (`MS_THREADS`), and the hyper server in [`rust/`](rust) (two tokio workers, release with LTO) joins the comparison. Ranges cover both rounds.

| Measurement | Manuscript | hyper |
| --- | ---: | ---: |
| `/health` req/s | 113k–119k | 114k–119k |
| `/user/42` req/s | 107k–108k | 115k–116k |
| `/top?n=10` req/s | 53k–54k | 53k–56k |
| `/health` p99 | 2.2 ms | 1.9–2.7 ms |
| Resident memory after `/health` load (separate run) | 10 MB | 4 MB |
| Resident memory, 10,000 idle connections | 62 MB | 104 MB |
| `/health` req/s beside 10,000 idle connections | 105k | 111k |

Throughput and tail latency are at parity with hyper. `run.sh` prints resident memory after the `/io` rows, which hyper does not serve, so the printed 57 MB against 4 MB is not a comparison: the `/io` payloads and pool threads account for the difference (10 MB after `/health` load alone). The suite's Manuscript server also failed to compile on main (a discarded `Result` in the worker handshake) until this change.

### 2026-10-30, acceptor and serving workers

`Listener.accept_raw` on the main thread, `HttpServer.adopt` in each worker, connections dealt round robin (`design/proposals/http-server-multicore.md`, stage 1). Server on CPUs 0-1 (main thread and workers share them), load on 2-3, shared 4-CPU Linux VM (+/-10% between runs), 64 keep-alive connections for 4 s per row (`load`), 32 connection-per-request clients for the last column (`Connection: close`, a Go dialer, scratch). Two rounds each.

| Manuscript | `/health` req/s | `/top?n=10` req/s | new connections per second |
| --- | ---: | ---: | ---: |
| 1 thread (`serve`) | 124k, 124k | 27.6k, 27.1k | 40.2k, 40.2k |
| 2 workers | 208k, 197k | 63.9k, 64.4k | 36.4k, 34.4k |
| 4 workers (2 CPUs) | 179k, 193k | 64.2k, 66.0k | 34.7k, 31.3k |

The CPU-bound handler scales 2.3x on two cores (the shared-listener workers reached 58k to 61k on the same rows, and with an uneven spread). Tiny requests gain 1.6x; the load generator takes the other two CPUs. Connection-per-request throughput is 85% to 90% of one thread with two workers: every connection pays the accept loop and a channel send, and the 2 CPUs are shared by acceptor and workers. Four workers on two CPUs add nothing, as expected.


### 2026-10-31, `serve_cores`

`MS_THREADS=n sh bench/perf/web/run.sh 4` on `f3e8d95e`: the Manuscript server is `serve_cores(listener, serve_worker, n)` (acceptor on the main thread, `n` serving workers, connections dealt round robin). Shared 4-CPU Linux VM (+/-10% between runs), servers on CPUs 0-1, load on 2-3, 64 keep-alive connections, 4 s per row, two rounds. The Go server in `go/` is the comparison; it ran in each pass.

| Server | `/health` req/s | `/user/42` req/s | `/top?n=10` req/s | `/health` p99 | `/health` req/s beside 10,000 idle connections |
| --- | ---: | ---: | ---: | ---: | ---: |
| Manuscript, 1 worker | 110k, 118k | 104k, 114k | 27k, 31k | 1.5-1.7 ms | 98k |
| Manuscript, 2 workers | 152k, 180k | 158k, 164k | 70k, 70k | 1.3-1.4 ms | 166k |
| Go (2 CPUs) | 99k-104k | not run | 42k-44k | 3.2-4.1 ms | 92k-97k |

Two workers scale the CPU-bound `/top` row 2.3x and tiny requests 1.4x to 1.6x, and pass Go on every row on the same two CPUs, with a lower p99. Resident memory is 56 MB with one worker and 58 MB with two (this includes the `/io` payloads). Not measured: skewed load (a few long-lived connections) and more than two server CPUs, which need a larger machine than this VM.

### 2026-11-03, `serve` on promises

`serve(address, handler, HttpServerOptions(cores: n))`: the accept loop is a promise and each connection is a promise the runtime places on a scheduler thread (`main.ms` takes `[threads]` as `cores`). Compared on the same machine, back to back, with the code before this change (`04b3acec`, `serve_cores` with `n` workers). Shared 4-CPU Linux VM (+/-10% between runs), `MS_THREADS=n`, server on CPUs 0-1 and load on 2-3 (n = 1, 2) or both sharing all four (n = 4), 64 keep-alive connections, 4 s per row, two rounds (`/user/42` only for n = 1, 2). Commands: `taskset` as in `run.sh`, load generator `bench/perf/web/load`.

| Threads | Row | Before | After |
| ---: | --- | ---: | ---: |
| 1 | `/health` req/s | 139k, 145k | 123k, 127k |
| 1 | `/user/42` req/s | 124k, 131k | 122k, 123k |
| 1 | `/top?n=10` req/s | 25.9k, 25.6k | 24.5k, 26.3k |
| 2 | `/health` req/s | 217k, 213k | 210k, 226k |
| 2 | `/user/42` req/s | 227k, 232k | 230k, 231k |
| 2 | `/top?n=10` req/s | 58.6k, 56.9k | 57.7k, 58.4k |
| 4 | `/health` req/s | 213k, 206k | 196k, 220k |
| 4 | `/top?n=10` req/s | 92k, 93k | 89k, 89k |

Two and four threads are at parity. One thread is about 10% slower on `/health` (the tiny-request row); CPU-bound rows are unchanged. Not yet explained: the keep-alive path is the same Rust code, and the extra costs per connection (a server object, a promise) do not repeat per request. The 2026-10-31 table above ran on another day and is not comparable row for row.

### 2026-11-03, refcount removal

Same server source on the pre-change integration head `d34af765` and the no-refcount head `d6052382`, 5 s rounds: `/health` 157.6k/155.3k against 168.0k/174.2k req/s, `/io` 1,577/1,455 against 1,570/1,504, resident memory after load 93.5 MB against 89.4 MB, 2.54 system calls per request on both. No change beyond noise; the full tables, including the older `632c42ba` run, are in [refcount-removal-2026-11-03.md](../refcount-removal-2026-11-03.md).

### 2026-11-03, memory on the integration branch

`MS_THREADS=2`, 64 keep-alive connections, 4 s rounds, servers on CPUs 0-1 and load on 2-3, compared against the code before the stream, promise and file changes (`e8caa9612`, `serve_cores`).

| Row | Before (`e8caa9612`) | After (integration head) |
| --- | ---: | ---: |
| Resident memory after `/health`, `/user/42` and `/top` | 12 MB | 10 MB |
| Resident memory after `/io` | 54 MB | 86 MB |
| Resident memory, 10,000 idle connections | 59 MB | 205-284 MB |

- `/io`: `write_file_bytes` and `read_file` return promises, so each of the 64 in-flight requests owns its own 1 MiB copy of the payload (and the 1 MiB read result) while it waits for a pool thread. The old blocking natives borrowed the payload and ran one job at a time. Moving the payload instead of cloning it only moves the copy to the caller (measured 111 to 129 MB), so the library keeps the clone. Capping queued file jobs would cut it; that belongs to the promise runtime.
- Idle connections: each connection is a promise with its own task stack (two mappings, about 20 KB resident), where the old server kept connections in the reactor. A minimal `/health` server shows the same 205 MB at integration commit `a8ed3a5c0` and at the head, so the stream merges did not add it.

### 2026-11-03, memory after `/io`, and `/health` CPU per request

Revision `a460b7ef`, shared 4-CPU Linux VM, `/health` with 64 connections, 4 s, servers unpinned. Server CPU per request (user + system from `/proc/<pid>/stat`): Manuscript with 2 threads 15.1 µs (93k–104k req/s over two runs), hyper 12.3 µs (105k–114k req/s). System time is equal (about 8.5 µs); user time is 5.7 µs against 3.8 µs. The earlier 89k against 124k–143k came from a run where the servers shared cores with the load generator, and is not a stable gap.

Resident memory after 64 `/io` connections, one serving thread: 8 MB after `/health`, 111 MB after `/io`, flat afterwards. Cause and rejected allocator changes: [wiki](../../../design/wiki/benchmarks-and-performance/freed-large-blocks-stay-resident-after-an-io-burst.md).

### 2026-11-03, handler sweep and many connections

`HttpServer` swept every live handler promise once per ready request, so a round cost (ready requests × running handlers). Handler promises now sit in a slab, and a finished request task reports its slot, so a sweep touches only tasks that finished. `/health`, 2 threads, 4 s, shared 4-CPU VM, unpinned, two rounds each (before, after):

| Connections | req/s before | req/s after | p99 before | p99 after |
| --- | ---: | ---: | ---: | ---: |
| 64 | 113k, 111k | 122k, 115k | 3.4, 3.6 ms | 3.2, 4.4 ms |
| 1,000 | 84k, 79k | 91k, 92k | 25, 27 ms | 23, 23 ms |
| 10,000 | 16.8k, 16.5k | 19.5k, 17.6k | 757, 722 ms | 641, 689 ms |

Same load against the other servers (2 threads, same VM): 1,000 connections hyper 104k–111k req/s (p99 35–41 ms) and Go 56k (32–38 ms); 10,000 connections hyper 76k–82k (444–517 ms) and Go 38k–42k (436–715 ms). Manuscript is ahead of both at 1,000 connections and 4x behind hyper at 10,000. At 10,000 the profile no longer shows `work_over`; `strace -c` shows about one `munmap` and one `mprotect` per request: once more than 1,024 request tasks are in flight, finished task stacks are unmapped (`STACK_POOL`) and new ones are mapped, guarded and faulted in again. That is the next cliff.

### 2026-11-03, task stack pool at 10,000 connections

Once more than `STACK_POOL` (1,024) request tasks were in flight, every finished stack was unmapped and every new task mapped, guarded and faulted in a stack again (about one `munmap` and one `mprotect` per request, 3.5 minor faults per request, 9k–16k live mappings). The pool now holds up to 65,536 stacks, and when the scheduler is about to block it returns the pages of all but the newest 256 pooled stacks once (`trim_idle_stacks`), so a quiet server goes back to its working set. `/health`, 2 threads, shared 4-CPU VM, two rounds (before, after):

| Measurement | Before | After |
| --- | ---: | ---: |
| 10,000 connections, req/s | 22.6k, 20.3k | 59.6k, 56.3k |
| 10,000 connections, p50 | 528, 551 ms | 122, 131 ms |
| 10,000 connections, p99 | 677, 681 ms | 666, 272 ms |
| 1,000 connections, req/s | 77k, 87k | 84k, 91k |
| Resident memory under 10,000 connections | 72 MB | 190–227 MB |
| Resident memory 3 s after the load | 72 MB | 35 MB |

hyper on the same VM: 76k–82k req/s at 10,000 connections, p50 17–21 ms. Peak memory is higher because 7,000 or so request tasks are alive at once, each with its touched stack pages; before, the same tasks existed but their stacks were remapped each time. This does not change the number of live tasks or the 2-mappings-per-task limit (#2483), which the growable-task work addresses.

### 2026-11-12, gzip response bodies (#3613)

A gzip body spent its time in three places (sampled with `gdb` on one `/gzip/text` client): the inflate itself, copies from regrowing the decoder's output buffer from empty at every 4 KiB input step, and a software CRC32 (`crc32fast::baseline`), because `flate2` builds `crc32fast` without its `std` feature and so never detects the CPU's carry-less multiply. The decoder now reuses the delivered buffer's capacity, and `ms-std-net` enables `crc32fast`'s `std` feature (a feature of the crate already in the lock file, not a new crate).

`bench/perf/web/fetch/ms` against `bench/perf/web/fetch/go`'s `/gzip/text` (8 MiB, about 24 KiB compressed), 1 connection, 3 s, release builds of the same tree before and after, 4 interleaved rounds on a shared 4-CPU Linux VM (±10%). Go's client, same server and run: 469 and 488 req/s.

| Build | req/s |
| --- | --- |
| Before | 116, 112, 110, 116 |
| Buffer reuse only | 153, 143, 150, 143 |
| Buffer reuse and CRC detection | 224, 237, 228, 236 |

Still 2x behind Go: what remains is miniz_oxide's inflate (a raw, non-wrapping `flate2::Decompress` into a presized buffer decodes this body at about 3.6 GB/s here, but the streaming path cannot use that mode). A faster inflate backend (`zlib-rs`) would be the next lever and is a new dependency.

### 2026-11-12, hand-written C ceiling and the per-switch poll

`bench/perf/web/c/server.c` is an epoll HTTP/1.1 server in C (one loop per thread, `read` then `write` per request, `/health` and `/user/<id>` only); `web_bench.ms` builds it when `cc` is present and runs it for those two rows. Numbers below pin one server thread to CPU 0 and the load generator (`load/`) to CPUs 2-3, 64 keep-alive connections, 4 s, shared 4-CPU Linux VM (±10% between runs), three rounds for `/health`, two for `/user/42`. CPU per request is `utime + stime` from `/proc/<pid>/stat` over the run. With two server CPUs the Go load generator saturates near 185k req/s and cannot tell C from anything faster, so the one-CPU row is the comparison.

| Server, `/health`, 1 CPU | req/s | user µs/req | system µs/req |
| --- | ---: | ---: | ---: |
| C (epoll) | 178k–188k | 0.4–0.6 | 4.1–4.4 |
| Manuscript before | 108k–121k | 3.7–4.3 | 4.4–4.8 |
| Manuscript after | 121k–139k | 3.1–3.7 | 4.0–4.4 |
| Go `net/http` | 51k–68k | 7.9–10.1 | 6.6–9.5 |

`/user/42`: C 159k and 193k, Manuscript 102k before and 116k–126k after, Go 52k–54k.

Changes: `switch_away` called a non-blocking `epoll_wait` on every task switch while any task waited on a descriptor, so a batch of requests cost one `epoll_wait` each (`strace -c`: 16.9k `epoll_wait` for 16.2k requests; C: 393 for 25k). It now polls every 32 switches, and an empty queue still blocks in `reactor_wait`, which polls (1.5k for 23k requests). The request target's common case (no escapes, dot segments or doubled slashes) takes one pass and two allocations instead of eight. `Headers` shares its entries until written, so `HttpExchange.headers()` no longer copies every request header. `parse_request` starts with 32 header slots and retries with 256 only on a 431, instead of initializing 8 KiB per request.

Still 1.4x behind C, all of it user time (3.1–3.7 µs against 0.5 µs). Callgrind with a small allocator reservation (the [wiki note](../../../design/wiki/benchmarks-and-performance/callgrind-needs-a-smaller-allocator-reservation.md)): 16k instructions per request, about 30 allocations (14% of instructions in `__rust_alloc` and `__rust_dealloc`), 18 `msrt_cleanup_push` calls per request (6%), one promise and one task per request, and three `String` clones for method, path and query. Those are the next cuts.

### 2026-11-12, serving workers on every thread

With `MS_THREADS=2` the server ran on one core. `serve` makes one worker promise per core, but a promise started beside a native stream pinned to its thread (the serving handle) runs on that thread, so every worker started in the accept loop stayed there; the second thread never ran one. `/top?n=10` measured 21.2k req/s at one thread and 22.8k at two (the 2026-11-03 table above showed 2.3x), and the thread list showed one busy thread. `PromiseOptions(spread: true)` (`msrt_promise_start_spread`) places a promise on the least loaded thread and starts a thread when the limit allows, ignoring the pin; `serve` uses it for its workers.

Server on CPUs 0-1, load generator on CPUs 2-3, 64 keep-alive connections, 4 s, shared 4-CPU Linux VM (±10%), one round each:

| Threads | `/health` req/s before | after | `/top?n=10` req/s before | after |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 127k | 128k | 24.7k | 21.2k |
| 2 | 131k | 208k | 22.8k | 45.4k |

C (epoll, two threads) reaches 190k here, where the Go load generator saturates, so two Manuscript threads are now at the load generator's limit on `/health`.


### 2026-11-12, one core: per-request instruction cuts

Revision `76324add` plus this change. A raw exchange handler (`path()` and `send()` only, no `buffered`) measured 135k req/s against 130k for the buffered one, so the single-core gap to C (190k) and hyper (150k) is runtime user time spread across the request path, not the handler API. Callgrind (small allocator reservation, `/health`, exact request count from call counts): 15.2k instructions per request before; allocation and free 14%, `msrt_cleanup_push`/`discard` 6.5% (18 pushes per request from the buffered handler's calls through the `HttpExchange` interface), request parsing about 10%, one promise and one task per request about 8%.

This change: a finished task hands its cleanup and guard buffers to the next one (a new task grew them from empty, three reallocations per request); an empty `Headers` shares one `Arc` instead of allocating; `begin_request` counts `Host` fields once and skips the UTF-8 check of names `httparse` already returns as `&str`. Callgrind: 15.2k to 14.3k instructions per request (−6%). Wall clock on the shared VM moved by about the same amount but is inside the ±10% noise (one pinned core, 64 connections, 6 interleaved rounds: median 129k against 120k req/s).

### 2026-11-12, one core: cleanup registrations that grow

`serve_buffered` calls `method()`, `path()`, `query()`, `headers()` and `protocol()` through the `HttpExchange` interface, each a cancellation point, with one more owned value live each time. The `unwind` pass opened a new window per call and registered every live value again: 18 `msrt_cleanup_push` per `/health` request. A value born inside an open window now gets a push of its own and the window's single discard pops them all (not across a `msrt_cleanup_discard`, which can pop below the window). Callgrind, same tree before and after: 14,301 to 13,614 instructions per request (−4.8%).

### 2026-11-12, one core: instructions per request against hyper

Callgrind, `/health`, 64-connection load for 8 s, exact request counts, release builds: hyper (two tokio workers, the `bench/perf/web/rust` server) 6,733 instructions per request; Manuscript 15,217 before this series and 13,606 after #3700 and #3728. Hyper does half the work, so no single cut closes the gap; the remaining cost is spread over about 23 allocations, one promise and one task per request, and the conversions between the server's Rust state and the language's values.

This change: a runtime task started with `start_native` (the server's request and reactor tasks) skips the stack walk that records where a promise was started, since its starter's frames are runtime code with no source line (1.5%, plus one allocation); a header name with a single value keeps it inline instead of in a one-element list (`Headers::Values`, one allocation per header); `HttpExchange.protocol()` returns its static text without a `String` copy. 13,606 to 13,065 instructions per request (−4.0%).

Next change: `HttpExchange.method()`, `path()` and `query()` build the language string straight from the exchange state (`Str::new`, an `IntoAbi` for `Str`) instead of cloning a `String` that the native boundary copies again: 13,065 to 12,687 instructions per request (−2.9%). A thread-id change for `Bound` (replacing `thread::current().id()`, which clones an `Arc`) measured 0 instructions and was dropped.

### 2026-11-12, multiple CPUs with a C load generator

The Go load generator saturates near 185k req/s, so the earlier two-CPU comparison with C (208k against 190k) measured the generator, not the servers. `load/loadc.c` (epoll, one thread per load CPU, one request in flight per connection) reaches 430k and `multicpu.sh` runs Manuscript, C and hyper (`rust/`, now `server <port> <dir> [threads]`) side by side. Revision `0b727e4a`, 128 keep-alive connections, 4 s, two rounds, shared 4-CPU Linux VM (±10%). Load generator CPU use was 5.3 of 8 CPU-seconds on Manuscript and 7.6 on C, so the two-CPU rows are server bound. Req/s in thousands, both rounds:

| Endpoint, server CPUs (load CPUs) | Manuscript | C | hyper |
| --- | ---: | ---: | ---: |
| `/health`, 1 (3) | 99–115 | 179–195 | 125–131 |
| `/health`, 2 (2) | 209–255 | 368–434 | 230–266 |
| `/health`, 4 (shared with load) | 234–243 | 367–426 | 235–247 |
| `/user/42`, 1 (3) | 92–102 | 139–163 | 122–125 |
| `/user/42`, 2 (2) | 213–226 | 382–395 | 215–217 |
| `/user/42`, 4 (shared with load) | 245–251 | 363–397 | 245–261 |

Manuscript is about 0.55–0.6x of C at every size and level with hyper at two CPUs; at one CPU it is about 0.85x of hyper. The four-CPU row shares CPUs with the load generator, so it shows the ratio, not scaling. A three-CPU row (one load CPU) was limited by the generator and is not reported.

### 2026-11-23, plain TCP reads on the calling thread

After #6665 writes went straight to the socket, but every read still went through the one network loop thread (`uv_read_start`, epoll, wake the waiter). `ms_net_read` now reads on the calling thread first when no read is posted on the connection, the stream is plain TCP and the program has two or more scheduler threads (a connection that has no bytes yet waits on the loop as before; a count of posted reads and the `direct` fence keep the loop's stash, end flag and close ordering intact). On Windows the same path uses a non-blocking `recv` (libuv's Windows TCP reads are zero-length overlapped ones that take no bytes); it has not been run on Windows yet, which needs the Windows CI dispatched on the branch. A write the loop abandoned (`broken`) now makes the direct read decline.

`/health`, C port, release build, 128 keep-alive connections, 4 s, three runs each on the shared 4-CPU VM (±15%), server CPUs (load CPUs), req/s in thousands, median of three with the range:

| Server CPUs | Before (#6665) | After |
| --- | ---: | ---: |
| 1 (3) | 72 (54–74) | 74 (67–83) |
| 2 (2) | 73 (53–86) | 156 (152–173) |
| 4 (shared with load) | 95 (53–99) | 228 (206–235) |

The two-CPU row had regressed in #6665 (two worker threads plus the loop thread on two CPUs); with the loop out of the read path it doubles. One CPU is unchanged because a single scheduler thread keeps the loop path (without the gate: 58 against 62 on the same runs). hyper at the same sizes is 120, 218–233 and 245–261 (2026-11-22 run).

### 2026-11-23, request path: connection-owned buffers, task records reused, edge-triggered reads

Per request the Manuscript server did 24.2k instructions, 27.5 allocations and 1.2 context switches (the loop thread did the reads and writes). Changes (proposal `web-request-path.md`): the response head, staging arrays and date line are built in per-connection buffers; plain request paths skip the decoder; the content-type sniff and authority check switch on the first byte; finished task records are kept (up to 64 per scheduler) with their cleanup buffers; and, at one scheduler thread, plain TCP connections register once with a per-thread edge-triggered epoll set (`io/edge.c`) and read and write on the owner thread (reset, try the syscall, wait for the next edge only after `EAGAIN` or a short read), so the loop thread is off the data path.

`/health`, callgrind over `bench/perf/web/ms` at one scheduler thread, about 70k requests (instructions include the loop thread):

| | Before (main 642ba74c) | After |
| --- | ---: | ---: |
| Instructions per request | 24.4k | 14.3k |
| Allocations per request | 27.5 | 15 |
| Context switches per request | 1.2 | 0 |
| Syscalls per request | 2.4 (+0.3 poll/futex) | about 2.0 |

Throughput on the shared 4-CPU VM (±25% run to run, so not a result): 1 CPU medians 61k before, 54k–72k after; 2 CPUs 167k–218k before, 170k–202k after (two scheduler threads keep the loop path). Kernel time per request depends on the request rate, so the instruction count is the measure; at 14.3k instructions the server is still 2.1x hyper's 6.7k. Not done: the 4.4k instructions of the per-request peer-hangup watcher task (a promise-based replacement cost more than the task, 14.9k, and was dropped; the tasks thread plans a lighter fd waiter), the multi-thread edge path, kqueue and Windows.

## 2026-11-25: wordfreq loops over the text directly

`wordfreq` called `data.lower().fields_by(...)`, which builds a list of every word (112 MB, 55k page faults on the 22 MB input) before the loop reads it once; Rust's `split` is lazy. The Manuscript version now walks `chars()` and counts a `view` of each word, as the Rust loop reads slices of the text. Output is byte-identical. Min of 9, same machine: ms 302 to 254 ms, Rust 196 ms (ms / Rust 1.54x to 1.30x). Callgrind instructions rise 2330M to 2460M (+5.6%, a view per word); the saved time is allocation and page faults. `fields_by` itself still returns a list: its 1300-line MIR with four push sites is out of reach of list fusion, so a lazy form is the stdlib follow-up.

## 2026-11-25: functions stay internal in release builds

Same machine, min of 5, `ms` before and after the change (`export_all` removed): `sim` 202 to 143 ms (Rust 156 in the same run; the `heat` stencil alone 89 to 43 ms against Rust 40), `jsonsum` 200 to 160 ms, `jsonrt` 1159 to 1091 ms, `pargroup` 59 to 48 ms. Callgrind instructions: `sim` 1945M to 886M (-54%), `hashing` -3.4%, `interp` -2.6%, `dispatch` -2.6%, `lz` -1.8%, `csvgroup`, `exprparse`, `graph`, `logstats` and `objgraph` within 0.1%.

## 2026-11-25: parameters and closure captures start from what every caller passes

`workers` passes `chunk` (the loop variable of `0..128`) through a promise closure into `chunk_checksum`; the range pass took every parameter and capture as any `Int`, so the callee kept signed remainders, a negative-index path and an overflow check on `chunk * 7919`. A step before the range pass now joins what callers and `closure.new` sites pass, and the emitter tells LLVM that interval and the bounds the pass proved for loop parameters. Callgrind instructions, same machine, `ms` before and after, all 23 suite programs: `workers` 1129M to 771M (-31.7%; checked Rust 769M), `graph` 558.7M to 545.5M (-2.4%), every other program within 0.15% (`jsonrt` +0.06%, `pargroup` -0.14%). Recording the bounds in every function instead of only seeded ones gave `exprparse` -1.9% but `wordfreq` +0.7% (one loop phi's assume changed LLVM's loop), so it is limited to seeded functions. `workers` wall time against `-C overflow-checks=on` Rust, min of 5, 4 threads: 33 ms to 31 ms against Rust 29 ms (one thread: 105 to 99 ms).

## 2026-11-25: `extend` checks room inline and copies plain elements with one memcpy

`msrt_list_extend` called `ms_list_reserve` and `msrt_list_copy_range` (which tests the element descriptor again) even when the list had room. It now tests the room inline and copies plain elements with one `memcpy`. `lz` (520k extends of about 6 elements in `make_input`): 688.1M to 667.8M instructions (-3.0%); other suite programs unchanged.

## 2026-11-25: a file read runs inline when every other task is stalled

`pargroup` (2000 files, `map_concurrent` over 4 workers) sent each `read_file` through libuv's pool, since a worker had more than one task, although the others were parked on remote waits: strace counted 12466 futex, 3003 epoll_pwait and 3016 write calls (Rust: one futex), and four workers (50 ms) were slower than `MS_THREADS=1` (39 ms). `ms_fs_run` now runs the job inline when `ms_task_others_stalled()`, the test `pool_alone()` already uses. Same machine, min of 9: `pargroup` 41-50 ms to 17-21 ms (Rust 28-33 ms); callgrind 367.3M to 357.6M; `treegrep` unchanged.
## 2026-11-25: a string view that is only loaded and stored gets its own alloca

Slots that are never live together shared one frame alloca; a view cell that only loads and stores now gets its own, which SROA keeps in registers, and a pooled slot joins only a cell of its own size (a 16-byte view in an 88-byte cell kept its stores). Callgrind instructions, same machine, all 23 programs against `main`: `wordfreq` -1.7%, `concat` -1.5%, `csvgroup` -1.0%, `logstats` -0.7%, `report` -0.35%, `objgraph` -0.3%, `jsonrt` -0.3%, `strings` -0.1%, `dedupe` -0.1%; `exprparse` +0.22% (wall +0.4%, inside the spread of 0.8%), `jsonsum` +0.12% (wall -1.6%); the rest within 0.05%. Unsharing list slots as well gives `lz` -1.3% but `report` +1.2% wall (a register allocation change in its `main`), so that half is held.
