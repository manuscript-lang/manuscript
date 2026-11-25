# Cranelift as the Debug back end

* Status: **Proposed** (2026-11-25, d5b63adf0)
* Authors: [Claude](https://claude.ai/code)
* Implementation: not yet implemented
* Direction: Chinmay, 2026-11-25: "all of mir needs to be translated to cranelift", "we'll publish a version for us from there for all platforms, similar to llvm bundle", Cranelift built as a shared library behind a C shim, "no cranelift optimisation patches in the manuscript repo".

## Summary

- Problem: a Debug build spends most of its time in LLVM, even with the light pipeline and the basic register allocator.
- Change: a second emitter, `compiler/emit_cl`, turns MIR straight into Cranelift IR through the C API of `manuscript-lang/cranelift-bundle`, loaded by path like libLLVM, and writes the object directly. Release builds stay on LLVM.
- Decision requested: approve the emitter and the staged rollout; the default flips to Cranelift only after the gate below.

## Motivation

Debug is the edit-run loop. The Rust implementation had a Cranelift Debug route (`ms-clif`) that the C rewrite dropped; its history is at `660429d4`.

Measured on `d5b63adf0` (`make build`, linux/amd64, 4 cores) for a program that parses and prints a small YAML document through `@std/data/yaml.ms` (36,314 lines of MIR):

| Step | Wall | CPU |
| --- | ---: | ---: |
| `ms emit` (check, lower, MIR passes) | 0.10 s | 0.08 s |
| `ms build --build-type Debug` | 1.61 s | 3.68 s |
| `ms build --build-type Release` | 2.47 s | 7.12 s |

So about 94% of a Debug build is code generation and linking, and the front end is not worth tuning first. The Rust implementation had a Cranelift Debug route (`ms-clif`) that the C rewrite dropped; its history is at `660429d4`.

Measured with the emitter (same program, same machine): Debug wall 1.33 s to 0.50 s and CPU 3.3 s to 0.64 s (about 5x less CPU, 2.7x less wall); the binary is 5.06 MB against 4.15 MB.

## Detailed design

**The bundle.** `cranelift-bundle` builds one shared library per platform from Cranelift 0.136.0 with three small patches kept in that repo (x64 flag fusion, a `sink_inst` assertion, COFF arm64 relocations). It holds the same floors as llvm-bundle (glibc 2.28, macOS 12.0, static Windows C runtime), is about 3 MB, and has no Cranelift patch in this repo. Releases are tagged `cranelift-<version>-r<n>` with a `SHA256SUMS` file.

**Consuming it.** Same as the LLVM library:

- `cmake/toolchain/cranelift-lib.lock` pins the tag and the digest of each archive; `cmake/FetchCraneliftLib.cmake` downloads and checks it into `.artifacts/cranelift-lib` and prints the path, which `MS_CRANELIFT` overrides.
- `compiler/link/cranelift_inproc.c` loads it by path with the dynamic form of `cranelift.h` (a function table filled by `cl_bind`); the header is vendored with its digest in the lock. No link-time dependency.

**Emitter.** `compiler/emit_cl` mirrors `compiler/emit` file for file (leaf, memory, scalar, checked, call, term, record, option, list, string, data, closure, iface), reading the same `MirModule`, `MirLayouts` and `MirData`, so a MIR rule is decided once:

- A MIR value is a run of leaves, as in `emit_cx.h`: an `i64`, `f64` or `i8` Cranelift value each, sized integers widened in registers and narrowed in memory. A value over 16 bytes is passed as the address of a stack slot; a multi-leaf result goes through a hidden first pointer. Both the calling convention and the symbols are unchanged, so Debug objects link with runtime and LLVM-built objects.
- Block parameters replace phis; the edge copies and repeated switch targets get a trampoline block, as `emit_term.c` does. Checked arithmetic uses `ms_cl_ovf` and a cold block that calls the same `msrt_post_*` fault functions.
- Frames: Cranelift has no slot sharing, so a function's `slot` values are `ms_cl_slot`s; `emit_slot_pool`'s sharing is not ported until a frame measurement says Debug needs it (deep recursion is the risk; stage 3 measures it).
- The wide-value cells, poison fills and purity hints exist for LLVM's optimizer and are not ported.
- A function the emitter cannot write is reported by name, as `emit_module`'s `why` does. While the emitter is incomplete, any such function sends the whole build back to LLVM; a build never mixes the two for one program.

**Parallelism.** The library compiles on its own worker threads (`ms_threads`, default one per core): `ms_cl_fn_end` queues the function, `ms_cl_finish` writes functions in declaration order, so the object is the same however the workers interleave. The emitter needs no thread of its own and no unit splitting.

**Debug info and fault tables.** The shim writes DWARF 4 line tables (one CU with `DW_AT_ranges`, a subprogram per function, column = the module-wide scope number) matching what `emit_debug.c` gives LLVM. `ms_cl_func_ranges` and the late relocations feed `mir_fault_tables`, so the fault-table reader sees the same names, lines and scopes. Type and variable DIEs are not written; main's LLVM route emits line tables only.

**Link.** The object is a normal ELF, Mach-O or COFF file for the existing `lld` step; no assembly text and no asm tables scan.

## Fit with the language

- **Memory model:** no change; the emitter lowers the same ownership ops.
- **Platforms:** the bundle builds and smoke-tests on six platforms in CI, Windows arm64 included.
- **Names and syntax:** none added. `--backend` is not a new flag: the route is chosen by build type, with `MS_BACKEND=llvm|cranelift` for diagnosing.

## Measured benefit

Debug build CPU is about 5x lower on the YAML program (Motivation). 157 fixtures built and run on the route with output identical to LLVM, none fell back. Gate before Debug defaults to Cranelift: on the conformance corpus the Debug build is at least 2x faster in `ms` CPU time than LLVM Debug, run-time of the produced code within the tolerance the corpus tests already assume, and the largest-frame recursion fixtures pass.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `cmake/FetchCraneliftLib.cmake`, `cranelift-lib.lock` | fetch and pin the library | fetch on both Linux arches in CI |
| `compiler/link/cranelift_inproc.c` | load by path, bind the table | load and compile a one-function module |
| `compiler/emit_cl` | MIR to Cranelift IR | conformance corpus on the Cranelift route, op by op |
| `compiler/link/object.c`, `cli/pipeline.c` | choose the route; write the object directly | `ms run` and `ms build` on both routes |
| `src/layers.txt` | `compiler/emit_cl: base abi compiler/check compiler/mir compiler/opt` | `ms_lint` |

## Compatibility

Release output and the LLVM route are untouched. Debug objects change only once the default flips.

## Alternatives considered

- Do nothing: Debug stays bounded by LLVM's code generator.
- asmjit or GNU Lightning: a hand-written code generator is a project of its own and a source of bugs (Chinmay, earlier in this work); Cranelift is maintained, verified and already proved on this MIR in the Rust implementation.
- Cranelift as a Rust crate in this repo: rejected by the "fewer Rust, no Cranelift patches here" direction; the bundle keeps its patches outside.
- LLVM `-O0` plus FastISel: FastISel changes the line a fault trace reports (recorded in `llvm_inproc.h`).

## Stages

1. Lock, fetch and loader; a one-function module through the library. Gate: loads on all six platforms.
2. Emitter for scalar, control flow, calls and runtime calls, behind `MS_BACKEND=cranelift`, whole-build fallback. Gate: the corpus programs that use only these ops run.
3. The remaining ops (records, options, lists, strings, closures, interfaces, data) and fault tables. Gate: the full corpus on the Cranelift route; measure against the benefit gate.
4. Flip the Debug default.
