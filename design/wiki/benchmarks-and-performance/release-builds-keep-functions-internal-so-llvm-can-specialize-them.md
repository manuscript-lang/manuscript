# Release builds keep functions internal so LLVM can specialize them

Every `ms build` made each function external (`export_all`, "needed when fault tables name them"). LLVM's interprocedural passes work only on functions with local linkage and no escaping address, so `heat(500, 120)` never learned `n = 500`: the stencil kept its overflow and bounds checks on `y * n + x`, which Rust (same constant call) folds away, and could not vectorize. `sim` ran 89 ms against Rust's 40.

- The fault tables do not need external symbols. They are built from the assembly the code generator prints (`link_asm_tables`), where an internal function still has its label; traces through recursive and inlined frames print as before (`ms build` of a recursive faulting program, `MS_UNITS=4` too).
- `export_all` is gone: `emit_header` exports only `export` functions and the entry.
- Result (callgrind, min-of-5 wall): `sim` 1945M to 886M instructions, 202 to 143 ms (Rust 156 ms in the same run, 0.92x); `jsonsum` 200 to 160 ms; `interp` -2.6%, `hashing` -3.4%, `dispatch` -2.6%, `lz` -1.8% instructions; the rest within 0.1%.
- Why it matters beyond one benchmark: a checked loop vectorizes or drops its checks only when LLVM can see the loop bounds; any program that passes sizes as constant arguments to a function gets it. If a future change makes functions external again, `sim` regresses to 2x Rust; the nightly `perf-counts` gate should carry `sim`.
