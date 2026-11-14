# Perf bash, 2026-11-14: collections

Base `88287373`, Release `ms` from `make build`, rustc 1.99.1 `-O`, 4 vCPU Xeon VM, min of 3. Probes: [`collections-round1/`](collections-round1) and [`collections-round2/`](collections-round2) (`MS=./target/release/ms sh bench/perf/collections-round1/run.sh 3`), Manuscript over Rust, checksums equal.

Round 1 (maps, sets, sort, structs, trees, grids): every case 0.38x to 1.02x except `sort_strings` 1.32x and `list_ops` 1.37x (`list_ops` is `distinct`, `reversed`, `filter`/`map` and 200 `contains` scans; see round 2).

Round 2 (single list operations): `l_contains` 1.58x (a linear scan Rust vectorizes), `l_pq` 1.72x (500k `PriorityQueue` enqueue and dequeue), `l_flatten` 1.17x, the rest at or under 1.05x. `l_slices` is dead code in Rust. `l_enumerate_zip` (`for e in xs.entries()` over 2M elements) was 6.9x.

## `for e in list.entries()` builds no entry records

`list.entries()` built a list of `ListEntry` records (one allocation each) before the loop ran: 28 ms for 2M elements against 4 ms for `for i in 0..n` with `xs[i]`. A loop over `xs.entries()` where `xs` is a local or read-only parameter the body cannot change, and the loop variable is only read as `e.index` or `e.value`, now walks `xs` by index and reads the borrowed element.

| 2M elements, `i * v % 7` sum | before (ms) | after (ms) |
| --- | ---: | ---: |
| `for e in xs.entries()` | 28 to 31 | 3.2 to 4.0 |
| `for i in 0..xs.length()` with `xs[i]` | 3.8 to 4.7 | 3.6 to 4.0 |

A loop that passes `e` on, captures it, moves it, or iterates a list it changes keeps the old path.
