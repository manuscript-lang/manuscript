# Element-type matrix

Everyday containers with realistic element types against Rust (`rustc -O`): records with a `String` field, payload enums, `Optional` and `Result` of records, a generic `Pair[A, B]`, and `Deque`, `PriorityQueue`, `Map`, `Set` and `sort` over them. Every case prints a checksum; `run.sh` fails the row if they differ.

```sh
MS=./target/release/ms sh bench/perf/element-types/run.sh 5
```

## 2026-11-12: Linux x86_64

Release LLVM `ms`, shared 4 vCPU VM, min of 5, microseconds. Rust's default `HashMap` is SipHash and its allocator is glibc `malloc`, so ratios under 1 on allocation-heavy rows say little.

| case | ms | rust | ms / rust |
| --- | ---: | ---: | ---: |
| list-records | 60,760 | 117,475 | 0.52 |
| list-enums | 65,031 | 54,279 | 1.20 (noisy: 0.9 to 1.2 across runs, parity in isolation) |
| map-records | 34,513 | 41,443 | 0.83 |
| map-groups | 82,182 | 109,157 | 0.75 |
| optional-records | 9,900 | 69,747 | 0.14 |
| deque-records | 35,461 | 26,620 | 1.33 |
| pq-records | 70,087 | 60,988 | 1.15 |
| generic-pairs | 45,691 | 99,267 | 0.46 |
| result-records | 10,306 | 9,228 | 1.12 |
| set-records | 90,599 | 99,621 | 0.91 |
| sort-records | 107,058 | 93,675 | 1.14 |
| records-of-lists | 18,906 | 53,487 | 0.35 |
| nested-generics | 27,579 | 53,442 | 0.52 |
| generic-stack | 14,513 | 85,519 | 0.17 |

### Change: a user `hash()` is mixed before it indexes the table

`Set[Pt]` with `fn Pt.hash() Int: self.x * 1000003 + self.y` took 562 to 627 ms for 1M inserts and lookups (min of 3), 6x the rest of the matrix and 2x Rust's SipHash set. The map used the user's value directly, and a hash that is the identity of two small ints makes runs of consecutive values that collide under linear probing. `DynKey::hash` now passes the user value through `hash_int` (one 128-bit multiply): 103 to 139 ms. Strings, `Int` keys and plain-bits records were already mixed.

Remaining gaps are small: `Deque` of records, `PriorityQueue` of records (the `sift_down` cost recorded in `datastructures/results.md`) and `sort_by` of records with a closure comparator, all 1.1 to 1.3x.

### Tried and not kept

- `Deque` of records (1.0 to 1.3x between runs): `grow` is 25M of 84M instructions per 1M pushes, and nothing runs in the runtime; a list range-move primitive would save about 10% wall at most.
- Sort of 5-word records (1.14 to 1.25x): sorting between the list and its scratch buffer alternately, with no copy back per level, cut instructions 225M to 161M at 200k records but wall time at 1M records stayed within noise (219 to 256 ms against 227 to 326 ms), so it was dropped. The remaining cost is the indirect comparator call and branch misses.
