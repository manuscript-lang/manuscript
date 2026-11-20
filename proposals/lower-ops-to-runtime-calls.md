# Lower string, list, alternative and optional ops once, for every backend

## Summary

- The C backends (`emit_llvm.c`, `emit_qbe.c`) each cover only scalars, records, calls and data; the Rust LLVM emitter spends 2,034 lines in `mir_llvm/{lists,enums,glue,strings}.rs` and 983 in `glue_llvm.rs` on the other ops (LLVM-text builders, so not a one-for-one line count).
- Add one pass, `mir_lower_ops` (`compiler/src/mir_lower_ops.c`), that rewrites those ops into `call.rt`, loads, stores, arithmetic and branches before any emitter runs. Emitters print scalars, memory, calls and data only.
- Decision requested: build it, starting with strings and clone/drop (stage 1), not one emitter at a time.

## Status

Proposal, 2026-11-20, checked against `origin/main` at `72a07024f`. The coordinator chose a shared pass over per-emitter lowering.

## Problem

- Measured: across 64 corpus programs (`ms emit`, 42k lines of MIR) the top ops are `call.rt` 2430, `str` 2400, `clone` 1320, `take` 755, `alt.new` 544, `alt.tag` 434, `cleanup.push` 334, `opt.*` about 700, list ops about 300. Only `call.rt`, `iconst`, `type.*` and scalar ops are emitted today.
- Verified: `crates/ms-mir-llvm/src/mir_llvm/glue.rs` and `glue_llvm.rs` hold the inline string clone (`msrt_str_copy` behind a tag test) and drop; a second C emitter would copy that logic again.
- Precedent, weak: `mir_depth_lower` (`mir_depth.c:150`) rewrites `depth.enter` into memory ops and a call, but splits only the entry block. Mid-block splits have no API yet, so stage 1 needs none.
- Baseline: `ms_mir_qbe` on the emitted corpus MIR lists the unsupported ops; stage 1 is judged by that list shrinking.

## Design

- Signature: `bool mir_lower_ops(MirModule *m)`; the last pass before the emitters, after glue, expand_owned, unwind, depth and verification, so everything that reads `clone`, `drop`, `move.out` and `forget` as ownership markers (`mir_glue.c`, `mir_verify.c`) has run. The lowered module is not verified again: it holds no ownership markers by construction. Estimated size: 400 lines for stage 1.
- One rule per op, as a table `{op, type predicate, rewrite}`.
- Stage 1 rewrites only to forms that need no block split:
  - `clone`, `drop`, `drop.if` of plain data: the operand or nothing. `move.out`, `forget`: the operand or nothing.
  - `clone` of a string: `call.rt @msrt_string_clone(&s, &out)`; `drop` of a string: `call.rt @msrt_string_free(&s)`. The runtime tests the tag, so the pass writes no branch. Other types: a call of the glue function from `mir_glue_find`.
  - `str.len`: shifts and masks on the tag word.
- Later stages, each its own PR once the pass can split a block: `list.*`, `alt.*`, `opt.*`. Ops that move ownership (`alt.take`, `alt.unbox`, `opt.unbox`, `list.set`) must say what happens to the old value's drop before they land; stage 1 leaves them unsupported.
- Literals: `str` of 15 bytes or fewer is two constant words; longer names a read-only data symbol (bytes plus NUL). Not in stage 1: `mir_data` has no string symbols yet.
- `emit_qbe.c` rejects any op it cannot print, naming it, so a missed family is a clear error. Values over 16 bytes remain unsupported in QBE until a later stage.
- Release speed: the LLVM backend may keep its inline fast paths for hot ops later; the pass is the portable baseline and the reference for the debug backend. No emitter-specific case enters the pass.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `compiler/src/mir_lower_ops.c`, `include/ms/mir_pass.h` | the pass, stage 1: clone, drop, drop.if, move.out, forget, str.len | `compiler/tests/qbe/strings.mir` (runs the lowered program) |
| `compiler/src/emit_qbe.c`, `compiler/tests/qbe/` | call the pass; programs that clone and drop strings run | `make c-compiler-test` |
| `compiler/src/emit_llvm.c` | call the pass (the LLVM thread) | its `llvm-run.sh` |

## Alternatives

- Do nothing: two emitters each re-implement about 2,500 lines; they drift, and the debug backend stays unable to run real programs.
- Lower inside each emitter: the cost above, and each emitter owns the ownership rules.
- Lower in the C runtime only (every op a call): fastest to write, but a call per `list.get` and `opt.is_some` costs release speed; the table lets hot ops be inline later without a second pass.

## Open questions

- Which inline sequences LLVM release keeps is its thread's call; the pass must not block that.
