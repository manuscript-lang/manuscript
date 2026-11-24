[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Large programs compile as parallel LLVM modules

`emit_module` cuts a program above 256 KiB of function text per module into up to one module per core (`MS_UNITS=n` forces a count, 1 is off). Each module is optimized, generated and assembled on its own thread; design in `design/proposals/module-units.md`. Router test on 4 cores: Release 12.5 s to 3.9 s, Debug 4.4 s to 1.6 s.

- Fault tables stay, so each module writes its own `ms_tables_<n>` and module 0 the `MsTableSet` (ABI 4); `ms_frames_install` joins them. Cost: the binary grows about 1% and start-up 0.4 ms.
- The code generator's options are process-wide and differ between the generate and assemble steps, so every module finishes generating before any assembles (`link_generate`, `link_finish`).
- LLVM never inlined across functions anyway (`noinline` on every function); a module only loses folding of loads from static data (defined in module 0).
- Forcing `MS_UNITS=3` over the conformance run and test phases passes, apart from failures that also occur with one module.
