[Wiki](../index.md) › Benchmarks and performance

# Benchmarks and performance

Perf and agent benchmarks, profiling.

Two unrelated benchmarks exist; never mix their results. Lowering and runtime trade-offs are in [compiler.md](../compiler/index.md) and [runtime.md](../runtime/index.md).

## Pages

- [Performance and agent benchmarks are separate](performance-and-agent-benchmarks-are-separate.md): `bench/perf/` measures compiler/runtime speed (`stdlib/` ns per operation, `programs/` and `kernels/` whole-program comparisons); `bench/agent/` measures how well agents solve the same challenges in T…
- [Benchmarks are a profiling guide, not a gate](benchmarks-are-a-profiling-guide-not-a-gate.md): results are only comparable on one machine and revision; record the commit and machine with the table, as the result files do.
- [A win needs a baseline comparison, not just a smaller number](a-win-needs-a-baseline-comparison-not-just-a-smaller-number.md): keep the raw hand-written baseline (the C controls in `bench/perf/kernels/c`) and distinguish logical work elimination from faster execution of each source operation.
- [Shared collection helpers need conversion and union controls](shared-collection-helpers-need-conversion-and-union-controls.md): eliminating a redundant lookup in `List.distinct` reduced
- [Consume library checksums and separate allocation phase from local cost](consume-library-checksums-and-separate-allocation-phase-from.md): a returned checksum that the harness discards is not evidence that the work stayed observable.
- [Source-size gap versus TypeScript is lines and I/O ceremony, not syntax noise](source-size-gap-versus-typescript-is-lines-and-i-o-ceremony.md): `bench/agent/tokens.py` puts the hand-written reference solutions at ms 12.2k, rust 10.1k, go 10.1k, ts 8.3k tokens, so Manuscript is not below Rust (1.21x) or TypeScript (1.48x); the old ms reference…
- [Compare instruction counts first; a low-IPC gap points at libc](compare-instruction-counts-first-a-low-ipc-gap-points-at-lib.md): wall-clock on a shared VM moves by 2x between runs, so compare `valgrind --tool=callgrind` instruction counts of one kernel built in Manuscript and Rust (`rustc -C opt-level=3 -C overflow-checks=on`)…
- [Real programs lose to Rust on collection call counts, not codegen](real-programs-lose-to-rust-on-collection-call-counts-not-cod.md): on c13-inventory-orders (2026-10-23) Manuscript made ~1.0M map calls where the Rust reference made ~342k, at a lower per-call cost than Rust's SipHash map; the count was the whole 1.55x instruction gap.
- [Count page faults before tuning a native that builds big buffers](count-page-faults-before-tuning-a-native-that-builds-big-buf.md): building a parsed JSON document ran 2x slower through `ms` than in a Rust test of the same code, with identical instruction counts.
