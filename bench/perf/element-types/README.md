# Element-type matrix

Everyday containers with realistic element types against Rust (`rustc -O`): records with a `String` field, payload enums, `Optional` and `Result` of records, a generic `Pair[A, B]`, and `Deque`, `PriorityQueue`, `Map`, `Set` and `sort` over them. Every case prints a checksum; `run.sh` fails the row if they differ.

```sh
MS=./target/release/ms sh bench/perf/element-types/run.sh 5
```

## 2026-11-12: Linux x86_64 (fair string baseline)

Release LLVM `ms`, shared 4 vCPU VM, min of 5, microseconds. Record names are 32-byte strings: literals are `Cow::Borrowed` in Rust, as Manuscript literals are static, and computed names are owned. An earlier run with a Rust `String` per record showed Manuscript 2 to 6x ahead on `optional-records`, `generic-stack` and `list-records` only because Rust allocated and Manuscript did not; that was not equal work. Rust uses its default SipHash `HashMap` and glibc `malloc`.

| case | ms | rust | ms / rust |
| --- | ---: | ---: | ---: |
| list-records | 97,990 | 158,258 | 0.62 |
| list-enums | 68,583 | 76,092 | 0.90 |
| map-records | 25,591 | 34,393 | 0.74 |
| map-groups | 78,584 | 135,269 | 0.58 |
| optional-records | 7,989 | 5,327 | 1.50 |
| deque-records | 31,628 | 31,500 | 1.00 |
| pq-records | 76,736 | 63,027 | 1.22 |
| generic-pairs | 61,630 | 110,503 | 0.56 |
| result-records (before the Error change) | 18,530 | 6,432 | 2.88 |
| result-records | 8,971 | 5,871 | 1.53 |
| set-records | 128,035 | 133,191 | 0.96 |
| sort-records (before this change) | 109,000 | 42,000 | 2.5 |
| sort-records | 86,231 | 49,668 | 1.74 (Rust sorts in place, no clone) |
| records-of-lists | 20,582 | 59,187 | 0.35 |
| nested-generics | 32,776 | 55,383 | 0.59 |
| generic-stack | 14,686 | 53,470 | 0.27 |
| map-enums | 39,012 | 52,990 | 0.74 |
| string-chains | 50,611 | 78,510 | 0.64 |

### Change: an `Error` is 40 bytes and its `details` header exists only when a detail does

`Error` was 88 bytes: message 16, kind 16 and the seven-word `details` map header inline, and dropping one called the runtime to drop seven zero words. A `Map` or `Set` field of an indirect record is now one nullable pointer to its header, created by the first insert, so an error with a message and kind is a 40-byte block and its drop is a null check. `Error(...)` and `err.details` are unchanged in source. `result-records` 10.9 to 9.0 ms (min of 5 to 9, same machine, same session as the table above; the table's 18.5 ms row came from a noisier run).

### Change: a user `hash()` is mixed before it indexes the table

`Set[Pt]` with `fn Pt.hash() Int: self.x * 1000003 + self.y` took 562 to 627 ms for 1M inserts and lookups (min of 3), 6x the rest of the matrix. The map used the user's value directly, and a hash that is the identity of two small ints makes runs of consecutive values that collide under linear probing. `DynKey::hash` now passes the user value through `hash_int` (one 128-bit multiply): 103 to 139 ms. Strings, `Int` keys and plain-bits records were already mixed.

### Change: sorting records that own data uses the generated sort

`xs.sorted(fn a, b: a.kind - b.kind)` over records with a `String` field called the runtime merge sort through a comparator pointer, 2.4x Rust at 1M records (250 against 104 ms for the sort alone). Plain records already used a merge sort generated with the program, with the comparator inlined (111 ms). Records that own data now use it too, over two bitwise scratch copies of the slots (`msrt_list_shadow`) that own nothing, so a comparator that faults or is cancelled leaves the original list intact; the sorted slots are cloned into the result at the end. 200k records: 225M to 102M instructions; 1M records: 250 to 155 ms for the sort.

### Change: driftsort replaces the generated merge sort

The generated sort (`sortgen.rs`) is now a driftsort, the algorithm of Rust's `slice::sort`: natural runs (descending ones reversed), unsorted stretches that merge lazily into one, a stable quicksort with an equal-to-ancestor partition (`O(n log k)` for `k` distinct keys), and the old merge sort as the fallback past `2 log2 n` depth. The comparator is still inlined and the scratch still owns nothing. The Rust twin of `sort-records` now clones before sorting, as `sorted` does (the earlier 49,668 us sorted in place).

Callgrind, 200k records with a `String` field, 1000 distinct keys, `sorted` including building the list: 102.5M instructions before, 81.8M after, Rust (`clone` + `sort_by`) 110.1M. In-place `sort`: 103.1M, 82.4M, Rust 105.7M. Wall times for 1M records are in [`sort-shapes`](../sort-shapes/README.md); the owning-record rows there:

| case | before | after | rust | ms / rust |
| --- | ---: | ---: | ---: | ---: |
| owned records, 1000 keys, `sorted` | 142,361 | 117,956 | 121,671 | 0.97 |
| owned records, 1000 keys, `sort` | 142,492 | 122,998 | 93,247 | 1.32 |
| owned records, distinct keys, `sorted` | 139,667 | 147,804 | 133,937 | 1.10 |
| plain records, 1000 keys, `sorted` | 75,050 | 46,360 | 61,477 | 0.75 |
| plain records, distinct keys, `sorted` | 70,428 | 71,837 | 87,835 | 0.82 |
| plain records, nearly sorted, `sorted` | 60,141 | 55,859 | 67,474 | 0.83 |

`sort-records` above, 500k records: 65,988 us against 57,158 us for Rust's clone and sort (1.15). The in-place gap is the shadow copies and the clone back into the list that keep a faulting comparator safe, not the sort.

### Open gaps

- `result-records` (1.5x) is the cost of building and dropping an `Error` (40 bytes, one allocation) on 10% of calls against Rust's `Err(String)`; the success path alone is 1.4 ns per call. It is not a codegen gap.
- Found while writing `string-chains`: a `String` conditionally moved into `Map.update(key, 0, fn ...)` fails to build ([#3706](https://github.com/manuscript-lang/manuscript/issues/3706)); the case moves it unconditionally.

- `optional-records` (1.5x), `pq-records` (1.2x, owned by the heap thread), `sort-records` (1.15x against clone and sort: the remaining cost is the shadow copies and the clone of the result).

### Tried and not kept

- `Deque` of records (1.0 to 1.3x between runs): `grow` is 25M of 84M instructions per 1M pushes and nothing runs in the runtime; a list range-move primitive would save about 10% wall at most.
- A runtime merge sort that alternates between the list and its scratch buffer, with no copy back per level: instructions 225M to 161M at 200k records but wall time at 1M stayed within noise; the generated sort is the real fix.
