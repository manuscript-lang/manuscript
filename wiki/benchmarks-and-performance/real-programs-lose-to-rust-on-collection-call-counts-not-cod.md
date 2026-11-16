[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Real programs lose to Rust on collection call counts, not codegen

Verified: on c13-inventory-orders (2026-10-23) Manuscript made ~1.0M map calls where the Rust reference made ~342k, at a lower per-call cost than Rust's SipHash map; the count was the whole 1.55x instruction gap. It came from idioms the library made cheapest to write: `keys()` then `get` per key (because `entries()` copied every value) and `get` then `add` (because `if var x = m.get(k)` lowered to four map calls).

Apply when: a workload is slower than Rust or Go; before tuning a runtime call or the LLVM input.
Evidence: `tests/conformance/fixtures/e2e/accept/map-in-place.ms`, `crates/ms-lower/src/stmt.rs` (`map_walk_loop`), `crates/ms-lower/src/alias.rs` (`AStep::Key`).
Verify: count runtime calls per source operation with callgrind (`calls=` per callee) on the Manuscript and Rust builds before comparing per-call costs.

Update (2026-11-16, `3b2ef968`): c13 is still 1.8x Rust, now from `report`'s `orders := w.orders.values()` followed by `orders.filter(..)`, `.count(..)` and `.map(..).sum()`. A `values()` the checker lends is a shallow view, but `filter` returns an owned list, so every passing `Order` (a record with a `List[Item]`) is deep-cloned and later dropped: 17% of c13 instructions are `report` plus the `clone`/`drop` glue and allocator behind it (callgrind, 800 KB input; callgrind sends allocations to glibc `malloc`, so read the allocator rows as inflated). A 2000-order microbenchmark of `values().filter(..).length()` costs 2x the same count done in place. A filtered view cannot reuse `msrt_list_slice_view`: its `cap == 0` result is never freed, and a filtered list needs its own pointer array. The fix is fusing `filter`/`map`/`count`/`sum` chains over a lent source into one loop in lowering, not a faster `filter`.
