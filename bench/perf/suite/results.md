# Suite results

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
