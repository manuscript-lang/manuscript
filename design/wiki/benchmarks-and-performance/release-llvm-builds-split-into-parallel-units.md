[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Release LLVM builds split into parallel units

A monolithic module through one optimizer and one code generator took 350 s for the 122k-line `bench/perf/tools/compile_time.ms` workload (4 cores) and 16.9 s for 18.6k lines; cutting it into consecutive equal-size modules, one per core, gave 60 s and 6.4 s with identical output (Rust-era measurement; the C build keeps the design, see [large programs compile as parallel LLVM modules](large-programs-compile-as-parallel-llvm-modules.md)).

- Small programs stay one module so they keep whole-program inlining; `MS_UNITS=n` forces a count (1 turns it off).
- Cost: no inlining across units, and each unit parses the whole debug metadata. A function reached only from another unit stays a call.
- What remains serial is the single largest function and the metadata parse.

Evidence: `bench/perf/compile-time/README.md` (2026-11-03 section), `src/compiler/emit/emit_units.c`, `src/cli/pipeline.c`.
