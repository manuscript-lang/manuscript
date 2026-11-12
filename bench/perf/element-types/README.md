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
| result-records | 18,530 | 6,432 | 2.88 |
| set-records | 128,035 | 133,191 | 0.96 |
| sort-records (before this change) | 109,000 | 42,000 | 2.5 |
| sort-records | 86,231 | 49,668 | 1.74 |
| records-of-lists | 20,582 | 59,187 | 0.35 |
| nested-generics | 32,776 | 55,383 | 0.59 |
| generic-stack | 14,686 | 53,470 | 0.27 |

### Change: a user `hash()` is mixed before it indexes the table

`Set[Pt]` with `fn Pt.hash() Int: self.x * 1000003 + self.y` took 562 to 627 ms for 1M inserts and lookups (min of 3), 6x the rest of the matrix. The map used the user's value directly, and a hash that is the identity of two small ints makes runs of consecutive values that collide under linear probing. `DynKey::hash` now passes the user value through `hash_int` (one 128-bit multiply): 103 to 139 ms. Strings, `Int` keys and plain-bits records were already mixed.

### Change: sorting records that own data uses the generated sort

`xs.sorted(fn a, b: a.kind - b.kind)` over records with a `String` field called the runtime merge sort through a comparator pointer, 2.4x Rust at 1M records (250 against 104 ms for the sort alone). Plain records already used a merge sort generated with the program, with the comparator inlined (111 ms). Records that own data now use it too, over two bitwise scratch copies of the slots (`msrt_list_shadow`) that own nothing, so a comparator that faults or is cancelled leaves the original list intact; the sorted slots are cloned into the result at the end. 200k records: 225M to 102M instructions; 1M records: 250 to 155 ms for the sort.

### Open gaps

- `result-records` (2.9x): a `Result[Event, Error]` whose error arm builds an `Error` value on 10% of calls.
- `optional-records` (1.5x), `pq-records` (1.2x, owned by the heap thread), `sort-records` (1.7x: the remaining cost is the merge sort against driftsort and a deep clone of the result).

### Tried and not kept

- `Deque` of records (1.0 to 1.3x between runs): `grow` is 25M of 84M instructions per 1M pushes and nothing runs in the runtime; a list range-move primitive would save about 10% wall at most.
- A runtime merge sort that alternates between the list and its scratch buffer, with no copy back per level: instructions 225M to 161M at 200k records but wall time at 1M stayed within noise; the generated sort is the real fix.
