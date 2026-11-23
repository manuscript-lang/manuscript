# A list built by one loop and read once by the next never exists

`xs.map(f).filter(g).sum()` made a list per stage. The `fuse` pass (`src/compiler/opt/opt_fuse.c`, first late step) runs the reader loop's body at the builder's push and drops the list, its slot and its cleanup. The reader's accumulators move to stack slots that the backend turns back into registers.

- Measured (2026-11-23, `/tmp` microbenchmark of the `closures_20M` chain, 20,000 rounds of 1000 elements): staged chain 37 ms, hand-fused loop 9 ms, with the pass 9.1 ms. `closures_20M` 46 to 23 ms.
- It works on MIR after inlining and range analysis, so it needs no knowledge of `map`, `filter` or `sum`: any loop that pushes to a one-owner list of scalars, and any loop that reads it by counter once. A chain fuses one stage per call; the pipeline simplifies and calls it again until nothing changes.
- Owner decision (Chinmay, 2026-11-23): the order of faults between the two loops may change. If both would fault, the later loop's fault can now be reported. The Rust lowering fuse had the same rule.
- It refuses when either loop calls out, waits, or writes memory other than its own lists and slots, so effects never reorder. Calls that the inliner leaves out block it; closure specialization is the way to widen it.
- Scalar elements and accumulators only. Owned elements (strings, records) need ownership moved through the push and are not handled.
- Evidence: fixture `e2e/accept/list-chain-fusion`.
