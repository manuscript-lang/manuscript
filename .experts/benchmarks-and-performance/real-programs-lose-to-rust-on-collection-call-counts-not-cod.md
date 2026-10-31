[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Real programs lose to Rust on collection call counts, not codegen

Verified: on c13-inventory-orders (2026-10-23) Manuscript made ~1.0M map calls where the Rust reference made ~342k, at a lower per-call cost than Rust's SipHash map; the count was the whole 1.55x instruction gap. It came from idioms the library made cheapest to write: `keys()` then `get` per key (because `entries()` copied every value) and `get` then `add` (because `if var x = m.get(k)` lowered to four map calls). After walking maps in place in `for` headers and making `if var` on a map one lookup, the same program written with those idioms ran 184-216 ms against Rust's 173-206 ms. Adding `memory(read)`/`nounwind` attributes to pure runtime lookups in the LLVM declarations changed nothing: the competence binary was byte-identical and c13 moved +0.5% instructions, because LLVM already inlines user code into one function and the remaining cost is the calls themselves.

Apply when: a workload is slower than Rust or Go; before tuning a runtime call or the LLVM input.
Evidence: `tests/e2e/testdata/accept/map-in-place.ms`, `crates/ms-lower/src/stmt.rs` (`map_walk_loop`), `crates/ms-lower/src/alias.rs` (`AStep::Key`).
Verify: count runtime calls per source operation with callgrind (`calls=` per callee) on the Manuscript and Rust builds before comparing per-call costs.
