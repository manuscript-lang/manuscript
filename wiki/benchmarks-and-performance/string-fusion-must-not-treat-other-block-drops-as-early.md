[Wiki](../index.md) › [Benchmarks and performance](index.md)

# String fusion must not treat other-block drops as early

Verified (2026-11-09, `c36-bank-ledger`): `strfuse` skipped any concat chain whose leaf was dropped in another block, so an interpolation using a variable also used on a sibling `return` path built `string_fmt2` plus `string_concat`, and a 10-piece interpolation kept ten concats and seven `int_to_string` temporaries. A drop is early only when its block reaches the join without redefining the leaf (`Info::dropped_before`). Fixing it cut c36 instructions 6.8%.

Apply when: changing `crates/ms-mir/src/opt/strfuse.rs` or any pass that moves a use later than the original operations.
Evidence: [results](../../bench/perf/perf-bash-2026-11-09.md), test `a_leaf_dropped_on_a_sibling_path_still_fuses`.
Verify: `MS_EMIT_OPT=1 ms emit` shows no `int_to_string` or lone `string_concat` left in an interpolation.
