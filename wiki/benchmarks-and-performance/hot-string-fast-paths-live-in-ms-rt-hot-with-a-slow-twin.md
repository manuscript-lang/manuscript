[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Hot string and set fast paths live in `ms-rt-hot` with a slow twin

Verified: callgrind on the engineering suite (2026-11-12, `bench/perf/structural-gaps/README.md`). Moving `index_of`, `view`, `scalar_at`, `parse_int`, `length`, `starts_with`, `ends_with` and `Set[Int]` `contains` into `ms-rt-hot` cut `wordfreq` 9.5%, `logstats` 5%, a `Set[Int]` contains-then-add loop 50% and the `mixed.ms` case e 12%. `logstats` is still 2.9x C: its cost is list and piece allocation, which inlining cannot remove.

- Placement rules live in `crates/DESIGN.md` ("Where a new function goes"). Chinmay's direction (2026-11-12): whole-runtime IR was rejected again (see `proposals`/`architecture/runtime-lto-proposal.md`: duplicated statics, minutes of `opt`); the answer to blind spots is to keep moving small pure fast paths into `ms-rt-hot`, with the rest behind `*_slow` twins. Lists (`at`, `get`, `first`, `last` of word elements), `Bytes` reads and the numeric compares moved that day.
- A function can be hot only if it allocates nothing, faults nothing and owns no state. An operation with a fault or a rare slow case (`view` bounds, `scalar_at` index, non-ASCII `length`) keeps the fast case in `ms-rt-hot` and calls a `*_slow` or `*_long` twin in `ms-rt` for the rest; the signature stays integers only.
- Test the ASCII case with the flag or the inline bits (`short_ascii`), never `[u8]::is_ascii` on a short string: that one change turned a 12% loss on `length` into a 12% gain.
- A fast path that depends on a layout (`Set[Int]` slots of 16 bytes) is chosen by `word_map_symbol` in `ms-lower/src/rtcall.rs` and checks `MapVal.desc` for a stamped key behaviour before it applies.
- Build a `memmem` searcher only for text of 128 bytes or more (`Needle::for_text`): it costs about 126 instructions, more than scanning a line.
- After editing `ms-rt-hot`, run `cargo xtask runtime` before any `cargo test` or `clippy --workspace`; the `ms-cli` build script rejects a stale archive.
