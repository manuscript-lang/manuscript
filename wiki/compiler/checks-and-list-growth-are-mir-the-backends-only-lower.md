[Wiki](../index.md) › [Compiler and build](index.md)

# Checks and list growth are MIR; the backends only lower

Decision (owner direction, 2026-11-16: language logic lives in MIR): `ms_mir::expand` runs after `unwind` and turns checked list access (`list.get/set/fill/addr`, `.nn` forms), `opt.unwrap` and `list.push` into compare, branch to a fault block, and the unchecked op (`list.get.u`, `list.fill.u`, `list.push.u`, `list.grow`). The growth rule (empty gives 4, else double) and the `checks` flag for these live only there. Fault and growth blocks are in `Func::cold`; backends lay them out of line and mark the branch unlikely. Overflow and division checks stay in the backends so LLVM keeps its intrinsics.

Reason: both backends decided the same checks separately. A backend test that compiles MIR directly must call `ms_mir::expand::run` first; a checked op reaching a backend is an `unreachable!`. Whether a runtime function never returns comes from `-> !` in `rt_symbols.txt` (`ExternDef::noreturn`), not a name list.

Apply when: adding a checked op or changing list growth or fault layout.
