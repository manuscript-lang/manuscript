# Runtime fast paths moved to `ms-rt-hot`

Evidence for moving list `at`/`get`/`first`/`last`, `Bytes` `get`/`view`/`starts_with`/`ends_with`/`index_of_byte`, the integer and float compares and `UInt64` division into `ms-rt-hot` (see `crates/DESIGN.md`, "Where a new function goes").

```sh
ms build --build-type Release bench/perf/rt-hot-moves/hot.ms -o /tmp/hot && /tmp/hot
```

## 2026-11-12: Linux x86_64

`faced39c` against the same plus this change, Release LLVM `ms`, 4 vCPU shared VM, minimum of 6 runs, microseconds.

| case | before | after |
| --- | ---: | ---: |
| `first()` + `last()`, 5M calls | 17,731 | 10,684 |
| `index_of_byte` hit 7 bytes ahead, 980 x 2000 | 8,751 | 5,439 |
| `List.get(i, 0)`, 20M reads | 7,662 | 7,668 |
| `Bytes.get(i, 0)`, 20M reads | 7,533 | 7,549 |

`get` on both was already inlined by lowering in this loop shape, so it does not move.
