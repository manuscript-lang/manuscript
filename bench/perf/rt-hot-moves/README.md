# Inline `first` and `last`

Evidence for emitting `List.first()` and `last()` inline (`ms-lower/src/native/list.rs`) instead of calling the runtime or `ms-rt-hot`; see `proposals/retire-ms-rt-hot.md`.

```sh
ms build --build-type Release bench/perf/rt-hot-moves/hot.ms -o /tmp/hot && /tmp/hot
```

## 2026-11-12: Linux x86_64

Release LLVM `ms`, 4 vCPU shared VM, minimum of 6 runs, microseconds, `first()` + `last()` 5M calls on a 1000-element `List[Int]`.

| version | time |
| --- | ---: |
| runtime call (`faced39c`) | 17,731 |
| runtime function in `ms-rt-hot` (an earlier draft of #3730) | 10,845 |
| Rust special case in `ms-lower` (merged) | 2,660 |
| stdlib `.ms` body (landed; the Rust special case is deleted) | 2,334 to 2,594 |

The other cases in `hot.ms` (`List.get`, `Bytes.get`, `Bytes.index_of_byte`) are not changed by this work; `index_of_byte` measured 8,751 against 5,439 us when moved into `ms-rt-hot`, which the compiler does not yet match (it needs a loop; see the proposal).
