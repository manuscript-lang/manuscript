# Heap parity with Rust, 2026-11-12

Does an algorithmically identical program emit more instructions in Manuscript than in Rust? `heap.rs` is Rust's `BinaryHeap<Reverse<(i64, u64)>>` (the real std type: one array of entries, hole-based `sift_up`, `sift_down_to_bottom`). `heap.ms` is the same algorithm in Manuscript: one `List[Entry]`, the hole held in locals, `sift_up` and `sift_down_to_bottom` as Rust writes them. Both enqueue 100,000 pseudo-random priorities (`order` is the enqueue index), dequeue all of them, and print the same weighted checksum.

```sh
rustc -C opt-level=3 -C overflow-checks=on -C codegen-units=1 heap.rs -o heap_rs
ms build heap.ms -o heap_ms
valgrind --tool=callgrind ./heap_ms 100000    # and ./heap_rs 100000
```

Callgrind needs the smaller allocator reservation ([wiki](../../../wiki/benchmarks-and-performance/callgrind-needs-a-smaller-allocator-reservation.md)); both programs allocate once. Linux x86-64, LLVM release build, instructions executed (`Ir`):

| program | instructions |
|---|---:|
| Rust `BinaryHeap` | 47.1M |
| Manuscript before | 56.0M |
| Manuscript after | 46.0M |

The standard-library `PriorityQueue` (two parallel lists, swap-based sift) is a different design and stays at 62.8M for the same workload; this page does not change it.

## Cause

The sift-down loop did 27 instructions per level against Rust's 22. Four of the extra were bounds checks on `heap[child]`, `heap[child + 1]`, the write to `heap[at]`, and a comparison that Rust makes branchless. The range pass could not prove the indexes in range, for four separate reasons:

1. **A join poisoned the list's length origin.** `heap` reaches the loop through a block parameter that merges two lists with different origins (the list as popped, and as it was when empty). The origin analysis marked everything derived from it `Mixed`, so the loop's list and the `list.len` taken before the loop never shared a length. A parameter that joins different origins is now an origin of its own, and lists derived from it by element replacement share it.
2. **`shl` was not modeled.** `child = 2 * at + 1` came back as top, so `child >= 0` was unknown. `shl` by a constant is now an exact interval.
3. **Widening jumped to the type bound.** A growing bound widened to `i64::MAX`, where `2 * at + 1` wraps to top, and the unrelated lower bound was lost in a cycle narrowing cannot repair. A growing bound now widens to `2^56` first and to the type bound only if it outgrows that.
4. **The guard's offset was pruned.** `child <= len - 2` was recorded as a relation to `len - 2`, which nothing reads later, so the relation was dropped before the use. A relation to `x +/- c` is now kept while `x` is live.

Result: every `heap[...]` in the loop is unchecked (`list.get.u`, `list.set.u`) and the loop is 22 instructions per level. The fixture is [`list_join_walk.mir`](../../../crates/ms-mir/tests/fixtures-opt/list_join_walk.mir).

## Remaining differences

Rust still skips checks the language cannot prove: the entry-hole read in `sift_up(pos)` and its writes check `pos` against the length (Rust uses `unsafe`), and the single-child case after the loop. Instruction totals are already at or below Rust's, so these are not chased here.
