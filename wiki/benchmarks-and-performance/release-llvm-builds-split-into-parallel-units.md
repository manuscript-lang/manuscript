[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Release LLVM builds split into parallel units

Release builds used to send one monolithic module through one `opt` and one `llc` process: 350 s for the 122k-line `bench/tools/compile_time.ms` workload (4 cores). Cutting the program into independent units first gave 60 s but no inlining across units (up to 7% slower code on `collatz`, 5% on `trees`). Now `llvm_obj::compile` keeps one module, runs `opt -passes='cgscc(inline)'` over the whole program, cuts the result with `llvm-split` into one part per core, and runs `opt -O3` and `llc` on each part in parallel.

- Parts are used only above 2 MiB of function text per part (`UNIT_BYTES`), at most one per core, so small programs are one module as before. `MS_LLVM_UNITS=n` forces a count (1 turns it off).
- More than one part disables the ELF anchor mode: every function keeps a hidden symbol and the tables address functions by symbol, as on macOS and Windows. Scope ids from each object are offset when the tables merge.
- The serial prefix (parse, inline pass, split) is about 1.6 s on `yaml-regressions.ms`; the whole build is 4.1 s against 7.8 s for one module and 2.8 s for independent units. The kernels run within noise of the one-module build.
- Only `cgscc(inline)` runs before the split: `default<O1>` costs 2 s more and gave the same code. The bundled `llvm-split` is the only extra tool.
- What remains serial is the single largest function and the whole-program prefix.

Evidence: `bench/compile-time/README.md` (2026-11-06 section), `crates/ms-cli/tests/llvm.rs::llvm_units_keep_fault_frames`.
