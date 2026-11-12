# Sort shapes

`xs.sorted(fn a, b: a.kind - b.kind)` and in-place `sort` over 1M records, against Rust's `clone` then `sort_by` (a stable driftsort). Records are 3 words (plain) or 5 words with a `String` (owning); `1000` keys means many ties, `distinct` means almost none, `nearly-sorted` is `k / 4 + k % 3`.

```sh
MS=./target/release/ms sh bench/perf/sort-shapes/run.sh 7
```

## 2026-11-12: Linux x86_64, driftsort

Release LLVM `ms`, shared 4 vCPU VM, min of 9, microseconds, checksums equal. The generated sort was a merge sort before this run (see [element-types](../element-types/README.md#change-driftsort-replaces-the-generated-merge-sort)).

| case | before | after | rust | ms / rust |
| --- | ---: | ---: | ---: | ---: |
| owned-dups-sorted | 142,361 | 117,956 | 121,671 | 0.97 |
| owned-dups-inplace | 142,492 | 122,998 | 93,247 | 1.32 |
| owned-distinct-sorted | 139,667 | 147,804 | 133,937 | 1.10 |
| plain-dups-sorted | 75,050 | 46,360 | 61,477 | 0.75 |
| plain-distinct-sorted | 70,428 | 71,837 | 87,835 | 0.82 |
| plain-nearly-sorted | 60,141 | 55,859 | 67,474 | 0.83 |

The in-place owning gap is the two bitwise scratch copies and the clone of the sorted slots back into the list, which keep a faulting comparator from leaving a duplicated owner; Rust sorts the list directly. Callgrind at 200k owning records with 1000 keys, whole program: `sorted` 102.5M instructions before, 81.8M after, Rust 110.1M; `sort` 103.1M, 82.4M, Rust 105.7M.
