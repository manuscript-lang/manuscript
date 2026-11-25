[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Large programs compile as parallel LLVM modules

`src/cli/pipeline.c` cuts a program above 64 KiB of function text per module into up to one module per core (`MS_UNITS=n` forces a count, 1 is off; `src/compiler/emit/emit_units.c` does the cut). Each module is optimized, generated and assembled on its own thread; design in `design/proposals/module-units.md`. Router test on 4 cores (Rust-era measurement): Release 12.5 s to 3.9 s, Debug 4.4 s to 1.6 s.

- Fault tables stay, so each module writes its own `ms_tables_<n>` and module 0 the `MsTableSet` (ABI 4); `ms_frames_install` joins them. Cost: the binary grows about 1% and start-up 0.4 ms.
- The code generator's options are process-wide and differ between the generate and assemble steps, so every module finishes generating before any assembles.
- LLVM never inlined across functions anyway (`noinline` on every function); a module only loses folding of loads from static data (defined in module 0).
- Forcing `MS_UNITS=3` over the conformance run and test phases passes, apart from failures that also occur with one module.

## What is left is IR volume

After the split, Release `ms test` time follows the LLVM input size, not the thread count (O2 against O3 and llc flags change nothing). Test bodies dominated it: each inlined `expect_equal` copied its failure path (about 350 IR lines per call), so a 534-line fixture produced 22 MB. A `test` block runs once, so lowering sets `MirFunc.runs_once` on it (not on `bench`) and the inliner uses the Debug threshold for call sites in it. Router test Release 5.4 s to 3.0 s, `json` 1.64 to 1.19 s, `fs` 2.17 to 1.07 s, Debug unchanged (Rust, Release: 3.07 s).

Module size: 64 KiB of function text per module (`UNIT_BYTES`), measured on 4 cores: `ms build` of `bench/perf/suite/jsonrt` Release 0.36 s to 0.22 s (Rust 0.25 s), Debug 0.28 s to 0.175 s; 32 KiB gained nothing more, and 256 KiB left such programs as one module.
