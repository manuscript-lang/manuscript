# Data-structure results

`sh bench/perf/datastructures/run.sh N` on a shared 4-CPU Linux VM (Intel Xeon @ 2.30GHz), Go 1.24, `rustc -O3`. Nanoseconds per operation, best of N; compare numbers only within one run, since this host varies by 10 to 20% between runs. Ratios below 1.00 mean Manuscript is faster.

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
