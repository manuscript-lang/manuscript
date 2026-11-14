# Perf bash, 2026-11-14: collections

Base `88287373`, Release `ms` from `make build`, rustc 1.99.1 `-O`, 4 vCPU Xeon VM, min of 3. Probes: [`collections-round1/`](collections-round1) and [`collections-round2/`](collections-round2) (`MS=./target/release/ms sh bench/perf/collections-round1/run.sh 3`), Manuscript over Rust, checksums equal.

Round 1 (maps, sets, sort, structs, trees, grids): every case 0.38x to 1.02x except `sort_strings` 1.32x and `list_ops` 1.37x (`list_ops` is `distinct`, `reversed`, `filter`/`map` and 200 `contains` scans; see round 2).

Round 2 (single list operations): `l_contains` 1.58x (a linear scan Rust vectorizes), `l_pq` 1.72x (500k `PriorityQueue` enqueue and dequeue), `l_flatten` 1.17x, the rest at or under 1.05x. `l_slices` is dead code in Rust. `l_enumerate_zip` (`for e in xs.entries()` over 2M elements) was 6.9x.

Round 3 ([`collections-round3/`](collections-round3): struct values in maps, memo maps, struct keys, enum lists, grid BFS with `Deque`, keyed sort, `group_by`, folds, string lists, set of records, nested maps): 0.28x to 1.35x; slowest are nested maps 1.35x, grid BFS 1.33x, keyed sort 1.18x, enum list 1.16x.

Round 4 ([`collections-round4/`](collections-round4): float sort, string sort, `index_of`, `remove(0)`, min/max/sum, windows, dedupe by sort, nested clone, closure lists, string set ops): 0.60x to 1.68x; `index_of` over strings 1.68x, `sorted()` of 300k strings 1.55x, float sort 1.29x. The string sort spends about 48 instructions per comparison in `msrt_string_compare` plus 22 in `memcmp` (callgrind), against `memcmp` alone in Rust; a first-word fast path could cut part of it but the gain is under 20%, so it is left open. `PriorityQueue` (1.72x) keeps FIFO order among equal priorities, which `BinaryHeap` does not; earlier passes in `datastructures/results.md` took the cheap wins.

No other case is over 1.5x on this machine; the three above (`contains` over `Int`, `index_of`/`sorted` over `String`, `PriorityQueue`) are 1.5x to 1.7x and noted rather than fixed.

## `for e in list.entries()` builds no entry records

`list.entries()` built a list of `ListEntry` records (one allocation each) before the loop ran: 28 ms for 2M elements against 4 ms for `for i in 0..n` with `xs[i]`. A loop over `xs.entries()` where `xs` is a local or read-only parameter the body cannot change, and the loop variable is only read as `e.index` or `e.value`, now walks `xs` by index and reads the borrowed element.

| 2M elements, `i * v % 7` sum | before (ms) | after (ms) |
| --- | ---: | ---: |
| `for e in xs.entries()` | 28 to 31 | 3.2 to 4.0 |
| `for i in 0..xs.length()` with `xs[i]` | 3.8 to 4.7 | 3.6 to 4.0 |

A loop that passes `e` on, captures it, moves it, or iterates a list it changes keeps the old path.
