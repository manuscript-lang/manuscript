[Wiki](../index.md) › [Compiler and build](index.md)

# Fault locations name the failing operation's statement, without columns

Decision: the user rejected per-call bookkeeping in generated code; a fault captures its frames where it is created, and the process runs scope-end cleanups in reverse order before aborting (design contract). Frames are `file:line in function` with no column, and a call spanning several lines reports the line of its statement's first line. A function's return-type position identifies its declaration, not a failing expression, so the located statement carries the position.

Apply when: adding lowered operations, inlining, source fault traces, or call fast paths.
Evidence: default frame regressions, default lowering, and the frozen `tests-e2e-testfaultsourcelocations-20` corpus fixture.
Evidence: [expected failures](../../../tests/expect-fail.txt), [call depth fixture](../../../tests/lang/closures/call-depth.ms), [fault and frame docs](../../../documentation/contributing/compiler/lowering/cleanup-and-faults.md).
Evidence: frame walkers and budget regressions, Windows native unwind anchor, [stack-size contract](../../../documentation/core-language/errors/faults.md).
Evidence: LLVM translation and six-target object tests, actual backend frame comparison, runtime fault definitions.
Evidence: glue selection and bounded-traversal regressions, deep-literal and source-frame guards.
Verify: `make conform` fault-location cases; preserve frame order, line numbers, and names.
Verify: native Windows shallow fault traces and the exact runaway-recursion corpus fixture; host synthetic-chain tests and cross-compilation alone cannot prove native unwind-entry identity.
Verify: generate and verify ELF, Mach-O and COFF for x86-64 and ARM64; run fault-frame checks (`make conform`) on supported native hosts. Cross-target object generation establishes code generation, not native execution or runtime ABI correctness on another operating system.
Verify: compare definition/edge permutations and repeated actual LLVM input captures; preserve acyclic selections, recursive clone/drop behavior, fault frames and the deep-literal compile guard. Deterministic attributes alone do not establish runtime performance.

C emitter: every function is `noinline` with `disable-tail-calls`. The fault tables carry only the MIR scope in a `.loc` column, so a callee that LLVM inlines (or a call it turns into a jump) loses its caller's frame in a release build (`bounds-fault-stride`, `testfaultsourcelocations-1`). The MIR inliner does the inlining and records the chain. A/B on `bench/perf/kernels/ms` showed no change beyond noise. Fault traces name a method `Type.name` (Optional receivers `Optional`) and show stdlib frames as `@std/...:<LINE>`.

Debugger info (2026-11-23, #5171): the tables step keeps `.loc` lines, so built programs carry a DWARF line table, one `DIFile` per source file (a MIR-inlined callee's lines sit in a `DILexicalBlockFile`). The `.loc` column is still the scope number. `MirFunc.names` is filled by lowering for by-value parameters only; the emitter writes `llvm.dbg.value` for scalar ones with scope 0. Names from an inlined callee (scope above 0) must not reach the caller's subprogram: two variables with one `arg:` make LLVM drop the module's debug info, and the fault tables lose their frames, silently, with the in-process LLVM. Subprogram names use the source name without `linkageName`, or gdb shows the symbol (`work.1`). `cmake/DebugInfoCheck.cmake` (ctest `debug_info`) stops a built program in lldb or gdb at `work` and checks the parameters.
