[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Real programs lose to Rust on collection call counts, not codegen

Verified: on c13-inventory-orders (2026-10-23) Manuscript made ~1.0M map calls where the Rust reference made ~342k, at a lower per-call cost than Rust's SipHash map; the count was the whole 1.55x instruction gap. It came from idioms the library made cheapest to write: `keys()` then `get` per key (because `entries()` copied every value) and `get` then `add` (because `if var x = m.get(k)` lowered to four map calls).

Apply when: a workload is slower than Rust or Go; before tuning a runtime call or the LLVM input.
Evidence: `tests/conformance/fixtures/e2e/accept/map-in-place.ms`, `crates/ms-lower/src/stmt.rs` (`map_walk_loop`), `crates/ms-lower/src/alias.rs` (`AStep::Key`).
Verify: count runtime calls per source operation with callgrind (`calls=` per callee) on the Manuscript and Rust builds before comparing per-call costs.

Update (2026-11-16, `3b2ef968`): c13 is still 1.8x Rust, now from `report`'s `orders := w.orders.values()` followed by `orders.filter(..)`, `.count(..)` and `.map(..).sum()`. A `values()` the checker borrows is a shallow view, but `filter` returns an owned list, so every passing `Order` (a record with a `List[Item]`) is deep-cloned and later dropped: 17% of c13 instructions are `report` plus the `clone`/`drop` glue and allocator behind it (callgrind, 800 KB input; callgrind sends allocations to glibc `malloc`, so read the allocator rows as inflated). A 2000-order microbenchmark of `values().filter(..).length()` costs 2x the same count done in place. A filtered view cannot reuse `msrt_list_slice_view`: its `cap == 0` result is never freed, and a filtered list needs its own pointer array. The fix is fusing `filter`/`map`/`count`/`sum` chains over a borrowed source into one loop in lowering, not a faster `filter`.

Update (2026-11-18, `b4b25a2b`): c16-maze-bfs is 1.8x Rust (75 ms against 41, 3 MB of grid) with 1.34x the instructions (346M against 257M, callgrind). The extra is memory, not code: the grid is a `List[List[String]]` of one-character cells, 16 bytes each, and `flatten` copies it (maximum resident 100 MB against 27 MB for Rust's byte rows; user time 48 ms against 22). `l.chars().clone()` already builds one list, not two, and the per-element string copy in `copy_range` is a short bitwise loop (13 instructions per cell). Nothing in the optimizer closes this; it would take a smaller cell (a character or byte type, or a packed one-character string), which is a language and representation decision. c03 and c13 were closed in part by `String.slice` inline (c03 71.6M to 65.3M) and by walking `for x in xs.filter(f)` in place (c13 392M to 350M).

Update (2026-11-18, same revision): c14-dp-suite is not a gap. The workloads table's 1.47x came from one fast Rust sample (377 ms); alternating 21 runs by CPU time give ms 518 ms against Rust 627 ms, and callgrind 660M against 955M instructions. A MIR rule that turns the `compare`-based `Int.min`/`max` into one `icmp` changed nothing in a release build (identical instruction counts; LLVM folds it). Before chasing a ratio from the workloads table, repeat it alone with alternating runs and CPU time.


## `List.slice` of owning elements stays a copy (2026-11-18)

The checker borrows a `slice` only when the elements are `Int`, `Float` or `Bool` (`native_borrow.rs`): a by-value `for` over a view drops each element, which would free what the receiver still holds. Widening the lowering alone to `List[String]` (cap 0 view) is not enough for that reason. A safe version needs an alias-cell twin like `map.keys()` (new cell array, non-owning strings). On c09, `msrt_list_slice` is 2.5% of instructions (3.7% inclusive) and most pieces are inline strings, so the saving is at most a couple of percent. Not built; revisit only if a workload shows long strings in sliced lists.

Resolved (2026-11-18): Chinmay chose integer cells over a character type, so the c16 reference holds `List[List[Int]]` (`scalar_values()`). Instructions 345.7M to 108.0M, CPU 81 to 31 ms, against 40 ms for Rust. When a reference holds one-character strings in a hot grid, use scalar values; the type was the whole gap.
