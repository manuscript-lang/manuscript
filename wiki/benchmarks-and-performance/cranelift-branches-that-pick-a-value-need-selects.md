[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Cranelift branches that pick a value need selects

Verified: Cranelift never turns a branch into a conditional move. `Int.min` and `Int.max` inline to a branch whose two edges reach one block with different arguments, and in dynamic-programming loops the data decides the branch, so it mispredicts. `lower_term` in `ms-clif` now emits one `select` per differing argument at the speed levels (Debug keeps the branch).

Apply when: Cranelift code runs well behind LLVM on a loop that takes a min, max or clamp of loaded values.
Evidence: [Cranelift survey](../../bench/perf/cranelift-survey-2026-11-13.md); `MS_DUMP_CLIF=1` prints each function's CLIF before Cranelift compiles it.
Verify: `c14-dp-suite` under `MS_BACKEND=cranelift` runs in about 1.06 s, not 1.80 s; `objdump` of `edit` shows `cmov` in the inner loop.
