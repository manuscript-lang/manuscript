# `var` record parameters stay in the caller's slot

A `var` parameter or receiver of record type is read and written through the caller's pointer (`Local.slot`), not moved out into SSA leaves at entry and put back at every return. A method on a wide record (`Lines.next`, 13 leaves) used to load every leaf, spill most of them, and store them all back per call: 147 instructions per line against 75 now, and `c44-unified-diff` 24.0 to 16.2 ms (1.62x to 1.12x Rust).

- `ms-lower/src/func.rs` `bind_var_parameter` does it for `TyKind::Type`; other types (lists, strings, alternatives) are three words or fewer and keep the take/put form.
- A function that falls back to `slotify` (a closure changes the parameter) keeps the old form.
- `Bytes` indexing and `get(i, default)` lower to `list.get` (`Module::seq_elem` gives `uint8` for bytes) instead of `msrt_bytes_get`, so a one-byte read is a bounds check and a load.
- Evidence: `bench/perf/codegen-2026-11-12.md`; fixture `e2e/accept/in-place-var-records-and-bytes-reads`.
