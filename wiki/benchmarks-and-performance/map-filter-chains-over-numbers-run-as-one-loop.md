# `map`/`filter` chains over numbers run as one loop

`xs.filter(f).map(g).sum()` built a list per stage (allocation, a push per element, a pass to read it back): 2.0x Rust's fused iterator, 1.35x Rust's materialized version, on 2M elements.

- `ms-lower/src/fuse.rs` fuses a chain of `List.map`/`List.filter` calls ending in `map`, `filter` or the stdlib `sum` when every callback is a lambda literal of one by-value parameter whose body is one `return` of a reading expression (names, literals, operators, fields, indexing; no call), and the source, every stage and the result hold numbers or `Bool`. The loop runs each element through all stages and builds only the final list (or adds into the sum with the same checked `+`).
- Why the guard: callbacks then run per element instead of per stage. With no calls the only observable difference is which fault is reported when two stages would both fault. A lambda that calls anything (`x.min(3)`, a user function) keeps the staged lowering. Elements that need ownership (strings, records) were left out to keep drop rules out of the fused loop; extend it only with a test of every drop path.
- Result: 163 ms to 78 ms for 50 rounds of filter/map/sum over 2M `Int` (Rust: 95 ms fused, 120 ms materialized).
- Evidence: `bench/perf/codegen-2026-11-12.md`; fixture `e2e/accept/fused-list-chains`.
