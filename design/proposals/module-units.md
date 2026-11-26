# Compile large programs as parallel LLVM modules (design proposal)

## Summary

- Problem: one `opt` and one `llc` run over the whole program, on one core. The router test takes 14 s Release and 4.4 s Debug on 4 cores; the Rust CLI took 3.1 s and 0.5 s.
- Change: above a size threshold the emitter writes N LLVM modules (functions cut into runs of equal text), each is optimized, generated and assembled on its own thread, and the runtime joins N fault-table blocks.
- Decision requested: none; no syntax or language behavior changes. `MS_UNITS=n` forces a count (1 turns it off).

## Status

- Proposal, 2026-11-23, checked against main 3b93082fcc.
- Precedent: the deleted Rust CLI split Release modules the same way (`git show 660429d4:crates/ms-mir-llvm/src/program.rs`, wiki `release-llvm-builds-split-into-parallel-units`).

## Problem

- `bench` of `tests/lang/stdlib/router.ms`, `ms test`, median of runs on 4 cores, serial: Release 12.5 to 14.0 s (opt 5.7 s, llc 5.6 s), Debug 4.4 s.
- A prototype (`llvm-split -j4`, then `opt` and `llc` per part) built the 355k-line Release IR in 4.4 s against 11.3 s serial. The largest part (one 13k-line closure) bounds the speedup.
- The back end's IR reduction lowers the volume but not the shape: one module is one thread however small the IR gets.

## Design

- `emit_module` writes the functions as before, then `emit_split_functions` cuts them into up to `units` modules: each function goes where its midpoint falls, so runs have about equal bytes.
- Every module holds its functions and a `declare` of each function another module holds, made from the function's own header line. A non-exported `internal` function becomes `hidden`. Unit 0 defines the static data, the others declare it `external hidden`; debug metadata and the intrinsic declarations are repeated, since the parser drops what no function names.
- Count: `min(cores, 16, function bytes / 64 KiB)`, so a program under 128 KiB of function text stays one module. (It was 256 KiB until `ms build` of a 330 KiB program, `jsonrt`, took 0.36 s Release as one module and 0.22 s as four; LLVM inlines nothing across functions here, so a split loses no inlining.) `MS_UNITS` overrides both bounds.
- Fault tables stay: each module's assembly is scanned by the existing `link_asm_tables` over the functions it holds and writes its own block `ms_tables_<unit>`; module 0 also writes `ms_tables` as an `MsTableSet` (ABI 4: version, count, block pointers). `ms_frames_install` joins the blocks into one sorted block (strings, scopes and offsets moved past the earlier parts), so lookups, the profiler and the walker are unchanged.
- Phases: every module finishes optimize and generate before any starts assembling, because the code generator reads process-wide options (a different register allocator for the assemble step). In-process option setting is serialized and skipped when unchanged; the library is loaded before the threads start.
- Every function is already `noinline` to LLVM (MIR inlines before emit), so nothing is lost to inlining; what a module loses is folding of loads from another module's static data and `memory(none)` facts about its functions. The count follows the cores, so a machine with more cores writes more modules; `MS_UNITS` pins it.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `compiler/emit` (`emit_units.c`, `emit.c`) | cut, declare, hide | `MS_UNITS=3` over the run and test phases of the corpus |
| `compiler/link` (`object.c`, `asm_tables.c`, `llvm_inproc.c`) | two-phase object step, per-unit tables, locked options | same, plus a fault in a late unit |
| `runtime/core/frames.c` | join `MsTableSet` | `core_unit` set test |
| `cli/pipeline.c` | threads, count, extra objects to the linker | same |

## Alternatives

- Do nothing: Release stays 3 to 4 times the Rust time, which the #6807 completion rule forbids.
- Split opt only and relink one module: `llc` is half the time and stays serial; estimated 9 s.
- `llvm-split` style split of the finished IR: no control of data and tables, and the tool is not shipped.
- One shared table block with label symbols: thousands of hidden symbols, and a size word cannot span objects.
