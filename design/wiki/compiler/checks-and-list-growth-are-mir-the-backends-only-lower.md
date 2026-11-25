[Wiki](../index.md) › [Compiler and build](index.md)

# Checks and list growth are MIR; the backends only lower

Decision (owner direction, 2026-11-16: language logic lives in MIR): `mir_expand` (`src/compiler/mir/mir_expand.c`) runs after `unwind` and turns checked list access (`list.get/set/fill/addr`, `.nn` forms), `opt.unwrap` and `list.push` into compare, branch to a fault block, and the unchecked op (`list.get.u`, `list.fill.u`, `list.push.u`, `list.grow`). The growth rule (empty gives 4, else double) and the `checks` flag for these live only there. Fault and growth blocks are cold; the emitter lays them out of line and marks the branch unlikely. Overflow and division checks stay in the backends so LLVM keeps its intrinsics.

Reason: the Rust backends decided the same checks separately. Hand-built MIR must run `mir_expand` first; a checked op reaching the emitter is an internal error. Whether a runtime function never returns comes from the extern's `noreturn` flag, not a name list.

Apply when: adding a checked op or changing list growth or fault layout.
