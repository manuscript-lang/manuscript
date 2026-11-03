[Wiki](../index.md) › [Benchmarks and performance](index.md)

# MIR pass tables use `ValueMap` except where cloned per block

Verified: replacing `HashMap<Value, _>`/`HashSet<Value>` in `simplify`, `inline`, `ifconv`, `optparam`, `lastuse`, `sortgen` with `ms_mir::vmap::{ValueMap, ValueSet}` (a `u32` slot per value index into a dense entry vector; a bitset) cut `opt::optimize` by 12 to 14% instructions (cachegrind, rules-400, rules-2000, c25-log-analyzer). A slot-per-value `Vec<Option<(Value, T)>>` was slower on small programs because wide `T` made the table large; keep the index at four bytes per value.

`range.rs` keeps its `HashMap<Value, Itv>`: its environment is cloned per dominator-tree block, and cloning a value-indexed table costs O(values) where the retained hash map costs O(entries), which made `a_chain_of_loops_is_handled_in_linear_time` go from 1s to 22s.

Apply when: converting another per-function `Value` table. Check whether it is cloned or rebuilt many times per function.
Verify: `cargo test -p ms-mir`, plus before/after cachegrind instruction counts of `optimize` on a large generated program.
