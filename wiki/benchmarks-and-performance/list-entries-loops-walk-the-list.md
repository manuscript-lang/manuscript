# `for e in list.entries()` walks the list in place

`list.entries()` materialized a `List[ListEntry[T]]` (one record per element) before the loop: 28 ms against 4 ms for an indexed loop over 2M elements. `list_entries_walk` in `ms-lower/src/stmt.rs` recognizes the loop when the list cannot change in the body and the loop variable is only used as `e.index` or `e.value` (no call argument, capture or move). `entry_locals` holds the index and the borrowed element; `member` answers `e.index`/`e.value` from them. Any other use falls back to the built list.

Evidence: `bench/perf/perf-bash-2026-11-14-collections.md`; test `list_entries_loop_reads_index_and_value_in_place`. A general fix (a non-escaping record kept in registers) would help every short-lived record, but MIR has no scalar replacement of records today.
