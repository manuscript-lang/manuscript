[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A read-modify-write is one API, not a syntactic pattern

Verified (2026-11-09, #3190): the compiler matched `m.add(k, m.get(k).get(0) + 1)` to one probe, so only that spelling was fast and each new spelling needed its own key-conversion and aliasing rules (#2857, #2858). `Map.update(key, initial, change)` is now a native mutator lowered to one lookup (`map_update` in `crates/ms-lower/src/mapset.rs`); the checker already rejects a `change` that overlaps the receiver, so the slot stays valid across the call. The matcher was deleted: the 2M-count loop runs in 7.6 ms through `update` against 10.1 ms for the matcher and 13.9 ms for `get_or` plus `add`.

The first version of `update` through the general `msrt_map_slot_lent` was slower than `get_or` plus `add` (15.0 ms): the general entry point dispatches on descriptors out of line. Probing first with the inlined word lookup (`msrt_map_get_ptr_w8`/`_sw8` through `word_map_symbol`) and reaching the runtime only for an absent key fixed it. A new fast path must reuse the existing word-specialized probes, not a general entry point.

Apply when: a hot idiom costs two lookups; before adding a syntactic fast path to lowering.
Evidence: `bench/perf/results-2026-11-09.md` (last section), `tests/e2e/testdata/stdlib/map-update-differential.ms`.
Verify: `ms test tests/e2e/testdata/stdlib/map-update-differential.ms`; compare one program per spelling, minimum of many runs.
