[Wiki](../index.md) › Benchmarks and performance

# Benchmarks and performance

Perf and agent benchmarks, profiling.

- [Numeric parsing needs invalid-input performance controls](numeric-parsing-needs-invalid-input-performance-controls.md): valid-input gains can hide overflow and malformed-input regressions; preserve error precedence and equivalent Rust validation.

- [A win needs a baseline comparison, not just a smaller number](a-win-needs-a-baseline-comparison-not-just-a-smaller-number.md): keep the raw hand-written baseline (the C controls in `bench/perf/kernels/c`) and distinguish logical work elimination from faster execution…
- [Benchmarks are a profiling guide, not a gate](benchmarks-are-a-profiling-guide-not-a-gate.md): results are only comparable on one machine and revision; record the commit and machine with the table, as the result files do.
- [Compare instruction counts first; a low-IPC gap points at libc](compare-instruction-counts-first-a-low-ipc-gap-points-at-lib.md): wall-clock on a shared VM moves by 2x between runs, so compare `valgrind --tool=callgrind` instruction counts of one kernel built in Manuscr…
- [Consume library checksums and separate allocation phase from local cost](consume-library-checksums-and-separate-allocation-phase-from.md): a returned checksum that the harness discards is not evidence that the work stayed observable.
- [Count page faults before tuning a native that builds big buffers](count-page-faults-before-tuning-a-native-that-builds-big-buf.md): building a parsed JSON document ran 2x slower through `ms` than in a Rust test of the same code, with identical instruction counts.
- [Performance and agent benchmarks are separate](performance-and-agent-benchmarks-are-separate.md): `bench/perf/` measures compiler/runtime speed (`stdlib/` ns per operation, `programs/` and `kernels/` whole-program comparisons); `bench/age…
- [Real programs lose to Rust on collection call counts, not codegen](real-programs-lose-to-rust-on-collection-call-counts-not-cod.md): on c13-inventory-orders (2026-10-23) Manuscript made ~1.0M map calls where the Rust reference made ~342k, at a lower per-call cost than Rust…
- [Shared collection helpers need conversion and union controls](shared-collection-helpers-need-conversion-and-union-controls.md): eliminating a redundant lookup in `List.distinct` reduced instructions but common-case wall timings remained inconsistent; the List change w…
- [Singleton fast paths need small-heap controls](singleton-fast-paths-need-small-heap-controls.md): a large singleton win was rejected after small heaps and unchanged controls regressed in longer paired trials.
- [Source-size gap versus TypeScript is lines and I/O ceremony, not syntax noise](source-size-gap-versus-typescript-is-lines-and-i-o-ceremony.md): `bench/agent/tokens.py` puts the hand-written reference solutions at ms 12.2k, rust 10.1k, go 10.1k, ts 8.3k tokens, so Manuscript is not be…
- [Empty Set relations need no membership probes](empty-set-relations-need-no-membership-probes.md): skip empty-right disjoint traversal while preserving callback behavior; keep nonempty and unrelated Map controls.
- [Benchmark drivers are `ms run` programs in the flat `bench/tools/` directory](benchmark-drivers-are-ms-programs-in-one-flat-directory.md): an entry file imports only below its own directory, so drivers share one `lib.ms` there; `make bench-check` tests them.
