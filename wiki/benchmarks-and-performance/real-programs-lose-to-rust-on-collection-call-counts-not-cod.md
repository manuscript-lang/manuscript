[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Real programs lose to Rust on collection call counts, not codegen

Verified: on c13-inventory-orders (2026-10-23) Manuscript made ~1.0M map calls where the Rust reference made ~342k, at a lower per-call cost than Rust's SipHash map; the count was the whole 1.55x instruction gap. It came from idioms the library made cheapest to write: `keys()` then `get` per key (because `entries()` copied every value) and `get` then `add` (because `if var x = m.get(k)` lowered to four map calls).

Apply when: a workload is slower than Rust or Go; before tuning a runtime call or the LLVM input.
Evidence: `tests/e2e/testdata/accept/map-in-place.ms`, `crates/ms-lower/src/stmt.rs` (`map_walk_loop`), `crates/ms-lower/src/alias.rs` (`AStep::Key`).
Verify: count runtime calls per source operation with callgrind (`calls=` per callee) on the Manuscript and Rust builds before comparing per-call costs.
