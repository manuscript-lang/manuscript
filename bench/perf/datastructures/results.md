# Data-structure results

`sh bench/perf/datastructures/run.sh N` on a shared 4-CPU Linux VM (Intel Xeon @ 2.30GHz), Go 1.24, `rustc -O3`. Nanoseconds per operation, best of N; compare numbers only within one run, since this host varies by 10 to 20% between runs. Ratios below 1.00 mean Manuscript is faster.

## 2026-10-26

Revision: this branch on top of `2e1227ae`; five rounds of `run.sh`, ranges across the last runs.

| Operation | Manuscript | Go | Rust | vs Rust |
| --- | ---: | ---: | ---: | ---: |
| list append | 2.7–3.5 | 34–41 | 3.3–3.8 | 0.8–0.9 |
| list get (random) | 2.4–2.7 | 6.7–7.7 | 4.1–5.4 | 0.5–0.65 |
| list sort (Int) | 16.9–17.4 | 323–338 | 30–31 | 0.55 |
| list sort (record comparator) | 62–64 | 1275–1314 | 44–46 | 1.35–1.45 |
| Map[Int, Int] put and get | 34–35 | 71–74 | 72–73 | 0.48 |
| Map[String, Int] put and get | 38 | 58 | 87–92 | 0.42 |
| Set[Int] add and contains | 41–42 | 68–72 | 54–55 | 0.75–0.8 |
| String build, split, join, replace | 27–28 | 58–62 | 23–24 | 1.15–1.25 (was 2.04) |
| Bytes append | 1.1–1.8 | 3–3.5 | 0.7–0.8 | 1.4–2.4 |
| PriorityQueue enqueue and dequeue | 71–73 | 131–139 | 36–37 | 1.9–2.0 (was 2.14) |
| SortedMap add and contains | 190 | – | 149–151 | 1.26 |

What bounds the remaining gaps (callgrind, instruction counts):

- PriorityQueue: the comparator closure is now inlined (69.2M to 51.4M instructions for 100k enqueue and dequeue), leaving about 35 instructions per heap level, eight of them bounds checks across two lists. Rust's heap has no FIFO tie-break list.
- Record sort by comparator: generated merge sort against Rust's driftsort; the generated sort keeps the runtime's comparator call order.
- Bytes append: 12 instructions per byte, fully inlined; wall time here is dominated by page faults on the growing buffer.
- String pipeline: split, join and replace are one pass each with exact-size results; the rest is the substring search itself.
- SortedMap: random keys over a chunked array; cache misses dominate.
