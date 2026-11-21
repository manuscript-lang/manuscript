[Wiki](../index.md) › [Compiler and build](index.md)

# Checks and list growth are MIR; the backends only lower

Decision (owner direction, 2026-11-16: language logic lives in MIR): `ms_mir::expand` runs after `unwind` and turns checked list access (`list.get/set/fill/addr`, `.nn` forms), `opt.unwrap` and `list.push` into compare, branch to a fault block, and the unchecked op (`list.get.u`, `list.fill.u`, `list.push.u`, `list.grow`). The growth rule (empty gives 4, else double) and the `checks` flag for these live only there. Fault and growth blocks are in `Func::cold`; backends lay them out of line and mark the branch unlikely. Overflow and division checks stay in the backends so LLVM keeps its intrinsics.

Reason: both backends decided the same checks separately. A backend test that compiles MIR directly must call `ms_mir::expand::run` first; a checked op reaching a backend is an `unreachable!`. Whether a runtime function never returns comes from `-> !` in `rt_symbols.txt` (`ExternDef::noreturn`), not a name list.

`list.release l, from` (the shell of an owned list left after its elements were taken out) is not an emitter op either: `lower_ops` calls a function made by `mir_glue_list_release(m, ty)`, the same body as the list drop glue with a start index (negative counts from 0; a view, capacity 0, is skipped). One function per list type, made before any function is rewritten, so the emitter (and the Rust-diffed `glue` pass, which never sees it) need nothing. Tests: `src/compiler/tests/run/listrelease*.mir`.

Apply when: adding a checked op or changing list growth or fault layout.
