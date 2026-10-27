# Data-structure results

`sh bench/perf/datastructures/run.sh N` on a shared 4-CPU Linux VM (Intel Xeon @ 2.30GHz), Go 1.24, `rustc -O3`. Nanoseconds per operation, best of N; compare numbers only within one run, since this host varies by 10 to 20% between runs. Ratios below 1.00 mean Manuscript is faster.

## 2026-10-27 (Bytes append and SortedMap re-measure)

Revision: this branch on top of `main` after #1692 (`buildmove`); `run.sh 7` twice, plus callgrind and `getrusage` on the standalone 4M-byte append and 300k-key SortedMap programs.

| Operation | Manuscript | Rust | Ratio |
| --- | ---: | ---: | ---: |
| Bytes append (ns/byte, two runs) | 0.9 to 1.0 | 0.9 | 1.00 to 1.12 (was 1.39 to 1.55) |
| Bytes append, page faults (4M bytes) | 1053 | 1087 | 0.97 (was 2033 vs 1086) |
| SortedMap add and contains (ns/op, `run.sh`) | 191 to 199 | 207 to 217 | 0.92 |
| SortedMap add and contains, 300k keys, process min of 15 | 127 ms | 121 ms | 1.05 |
| SortedMap instructions, 300k keys | 328M | 252M | 1.30 |

Bytes: the earlier gap was the copy `build()` made of the whole buffer, which doubled page faults; `buildmove` moves the buffer for a builder that is not built again, so faults are at Rust's level. The append loop itself is still 13 against 8 instructions per byte (the sealed-flag test and the length write-back each iteration); wall time is within noise of Rust. SortedMap: wall time is at parity, with more instructions than `BTreeMap` that the cache misses hide.

## 2026-10-27 (PriorityQueue sift-down guards)

Revision: this branch on top of `9f41921f`; callgrind on 100k enqueue and dequeue, plus `run.sh 7` twice on the same host.

| Measure | Before | After | Rust |
| --- | ---: | ---: | ---: |
| Instructions, 100k enqueue and dequeue | 110.7M | 87.4M | 44.9M |
| ns/op (`run.sh 7`, two runs) | 112 | 97 to 100 | 81 to 97 |

`sift_down` now loops while `0 <= at < (size - 1) / 2`, so the range analysis proves the child indices non-negative and in range and drops their normalization and bounds checks (75 to 52 instructions per level); the one-child last level is handled after the loop. Without the explicit `at >= 0` guard the analysis lost the lower bound of `at` and kept the checks. What remains: the `orders` list is a separate list whose length the analysis does not tie to `heap`, and the comparator's checked subtraction.

## 2026-10-27 (SortedMap)

Revision: this branch on top of `d370bb89`; best of 10 runs of the `sorted_map_add_contains` row, same machine class.

| Operation | Manuscript before | Manuscript after | Rust |
| --- | ---: | ---: | ---: |
| SortedMap add and contains | 214 | 193 | 169 |

Chunks now split at 128 entries instead of 256. Split by operation at 300k keys: add 290 to 255 ns, contains unchanged at 138 ns, which already beats `BTreeMap` (157). The remaining gap is all in add: callgrind shows 58% of data-cache read misses inside `memmove` shifting chunk tails and the chunk-header lists. A three-level layout (segments of chunks, as a struct or as nested lists) made both add and contains slower and was dropped. As a struct list it first hit #1661 (a `var def` on a list element deep-copied it, 4 µs per add), fixed in the same change; retried after the fix it is still slower (add 317 vs 298 ns, contains 164 vs 137 ns at 300k keys, chunks of 64 or 128 and 32 or 64 chunks per segment), so the top-level shifts are not the cost. A B-tree written in Manuscript (nodes holding keys, values and children inline, split on the way down; 15 to 127 keys per node) was also slower: add 334 to 471 ns and contains 198 to 279 ns against 291 and 135 for the chunked layout in the same run, so it was not kept.

## 2026-10-27

Revision: this branch on top of `90e401c46`; same machine class, one `run.sh 5` before and after.

| Operation | Manuscript before | Manuscript after | Rust |
| --- | ---: | ---: | ---: |
| PriorityQueue enqueue and dequeue | 210 | 103 | 93 |

The 2026-10-26 heap moved entries with `List.swap`, which for every element type was a call into the runtime (about 55 instructions per swap, 63% of the benchmark). Swapping scalar elements is now two inline loads and two stores, and the heap sifts down to the bottom along the earlier child before sifting back up (callgrind: 317M to 111M instructions for 100k enqueue and dequeue). `fs.stat` did not regress against `c1b81215` on this host.

## 2026-10-26

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
