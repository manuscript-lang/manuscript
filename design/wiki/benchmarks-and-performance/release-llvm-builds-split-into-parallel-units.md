[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Release LLVM builds split into parallel units

Release builds used to send one monolithic module through one `opt` and one `llc` process: 350 s for the 122k-line `bench/tools/compile_time.ms` workload (4 cores), 16.9 s for 18.6k lines. `LlvmModule::finish_units` now cuts the functions into consecutive runs of equal byte size, each a complete module that only declares what another unit defines, and `compile_all` in `ms-build` runs one `opt`+`llc` per unit on its own thread. Result: 60 s and 6.4 s, identical program output.

- Units are used only above 2 MiB of function text per unit (`UNIT_BYTES`), at most one per core, so small programs keep whole-program inlining and their benchmarks do not change. `MS_LLVM_UNITS=n` forces a count (1 turns it off).
- More than one unit disables the ELF anchor mode: every function keeps a hidden symbol and the tables address functions by symbol, as on macOS and Windows. Scope ids from each object are offset when the tables merge.
- Cost: no inlining across units, and each unit parses the whole debug metadata. A function reached only from another unit stays a call.
- What remains serial is the single largest function (`ms_entry` of the synthetic workload is 33k IR lines and 40% of `opt` time) and the metadata parse.

Evidence: `bench/compile-time/README.md` (2026-11-03 section), `crates/ms-cli/tests/llvm.rs::llvm_units_keep_fault_frames`.
