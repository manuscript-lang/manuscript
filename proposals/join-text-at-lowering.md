# Join interpolated text at lowering, not in a MIR pass

## Summary

- Problem: lowering builds `"{a}:{b}-{c}"` as nested `string_concat` calls and `int_to_string` temporaries, then `opt/strfuse.rs` (653 lines) finds those exact runtime calls and rewrites them into one `string_concatN`/`string_fmtN`. A pass undoes what lowering just emitted.
- Change: lower interpolation and `+` chains of strings to the joined call directly, and a `StringBuilder.append` of an interpolation to appends of its pieces; delete the two fusions.
- Decision requested: build it only if the gates below hold; this is code removal, not a speed change.

## Status

Proposal, 2026-11-15, checked against `31b6eeb2`. Direction (Chinmay): the compiler makes no decisions by name and has fewer undo passes. Review: pending.

## Problem

- Verified (`ms-lower/src/text.rs:703-745`): `text()` folds parts left to right with `msrt_string_concat`; an `Int` part becomes `int_to_string` first. `expr.rs:838` does the same for `a + b`.
- Verified (`strfuse.rs`): `fuse_concat` merges a chain of at most 6 leaves into `msrt_string_concatN`, passing single-use `Int` leaves to `msrt_string_fmtN(mask, ...)` so no temporary string exists; `fuse_one` rewrites `strbuilder_append(b, built_text)` into per-piece appends (`strbuilder_append_int` for integers); `append_in_place` turns `s = s + piece` into `string_append`.
- Measured (27 suite and collections programs, release): `fuse_concat` fires in 26, `fuse_one` in 2 (`exprparse`, `report`), `append_in_place` in 1. Disabling `fuse_one` alone costs `exprparse` +14.8% instructions (12,651,384,338 to 14,520,139,785).
- Each fusion re-proves facts lowering already knows: the pieces are fresh temporaries with one use, and a piece dropped before the join would be used after its drop (`Info::dropped_before`, single-use and straight-line checks, 653 lines).

## Design

- `text()` collects its pieces (literal, string, plain `Int`, other values formatted to strings as today) into a list and emits one `msrt_string_fmtN` or `msrt_string_concatN` call per group of at most 6, then joins groups with the same call. Evaluation order and the early-return rule for `try` parts stay: a later `try` makes the earlier pieces held temporaries before the join, as now.
- `a + b + c` on `String` flattens the left-nested `Add` chain at lowering into the same call. A single `a + b` stays `string_concat`.
- A `StringBuilder.append(x)` whose argument is an interpolation or a `+` chain lowers to appends of its pieces after the sealed check; the decision is "the argument is a text expression", read from the HIR node, not a name list. The runtime role (`ExternRole::StrBuilderAppend`) is read from the declaration as today.
- `append_in_place` stays: an unoptimized build needs it to keep a loop that grows a string linear (`opt/mod.rs`, `run_append`). It is the one string pass left.
- No language, syntax or output change; user `to_string` results join as string pieces.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-lower/src/text.rs`, `expr.rs` | collect pieces, emit joined call; flatten `+` chains; builder-append pieces | conformance string fixtures; new fixture with a `try` part and a `+` chain over 6 pieces |
| `crates/ms-mir/src/opt/strfuse.rs` | delete `fuse_one`, `fuse_concat` and their helpers; keep `append_in_place` | `opt_strfuse.rs` tests move to lowering output checks |
| `crates/ms-mir/src/ir.rs`, `rtcall.rs` | drop `ExternRole` cases only the deleted code read | `make repo-check`, clippy |
| `bench/perf` | dated result section | before/after table |

## Alternatives

- Do nothing: no risk; the pass works and is guarded. It keeps a lowering that emits temporaries on purpose and a 653-line recogniser keyed on runtime call roles.
- Keep the pass, share its leaf gathering with lowering: still an undo pass.
- A write-into-destination sink protocol for every piece (including user types): needs a `to_string` write form, a language decision, not made here.

## Stages

1. `text()` and `+` chains join at lowering; `fuse_concat` deleted. Gate: executables of the 27 suite and collections programs and the instruction counts of `strings`, `exprparse`, `jsonrt`, `report` within 1% of main; `make conform` on Cranelift and LLVM; a formatting loop allocates once per interpolation.
2. Builder append of text expressions; `fuse_one` deleted. Gate: `exprparse` and `report` instruction counts within 1%.
3. Remove unused `ExternRole` cases; record the result in `bench/perf/` and the wiki.
- No-go: a stage that regresses a gate by more than 1%; keep the pass for that stage.

## Open questions

- None that change user-visible behavior.

## Result of stage 1

- Code: 239 lines added, 662 deleted under `crates/` (`fuse_concat`, its helpers and the tests of the deleted passes).
- Instruction counts against the same base, 17 suite programs: Release all within 1% (worst `regex` +0.91%, `jsonrt` +0.89%). Debug is lower on 15 (`strings` -6.3%, `graph` -17.6%, `concat` -10.2%) and higher on `interp` (+1.8%). The `interp` hot loop has the same MIR before and after; the difference is Cranelift register allocation of one function, which the extra `iconst` in the lowered join shifts. Not a lowering cost; recorded as a miss of the 1% gate.
- `fuse_one` stayed in stage 1; stage 2 below removes it.
- Ordering: `joined-text-piece-order` pins left-to-right pieces, a `?` that returns early running no later piece, and `+=` accumulation. Leak sweep (392 programs) and ownership counts (148) pass.

## Result of stage 2

- `builder.append(text)` for an interpolation or a `+` chain evaluates every piece, then appends each one (`msrt_strbuilder_append`, `_append_int` for a plain `Int`; more than eight pieces join first). `fuse_one`, its plan and leaf bookkeeping are deleted; `strfuse` is now only the in-place `s = s + piece` growth. The sealed-builder check stays in the runtime append, which runs before it writes.
- Instruction counts against main, 17 programs: Release all within 1% (worst `regex` +0.91%, `jsonrt` +0.89%, `exprparse` +0.22%). Debug: `exprparse` -7.2%, `regex` -6.5%, `jsonrt` -3.6%, `hashing` -2.9%, `strings` -5.9%, `concat` -10.2%; `interp` +1.8% (register allocation, see stage 1).
- The ordering fixture also covers an append whose middle piece returns early through `?`.
