# Frames in the hundreds of bytes: shared call temporaries, in-place `var` records

## Summary

- Problem: yaml `quoted.body` has a 2384-byte Debug frame. Measured (`llc -print-after=prologepilog` frame objects): two 520 B `Flow` cells 1040 B, per-call temporaries 664 B, other allocas 160 B, about 62 spill slots 500 B.
- Change, by size and risk: (1) share the per-call temporaries (`y<n>_<k>` argument copies, `s<n>` result areas) across blocks never live together, about -450 B; (2) forward `put S,v; take S` through effectful instructions for a private slot, so the record stops being parked in `slot Flow`; (3) keep a `var` record parameter in the caller's memory and read and write its fields in place, -1040 B; (4) find why about 62 values spill.
- Decision requested: none; no language change and no stdlib change. Chinmay's target is frames "in the hundreds of bytes".

## Status

Proposal, 2026-11-23, checked against `e47e2b0d0b`. Review (skeptical subagent): revise; this text covers its findings (slot-parked chains, unwind of a half-updated record, spills, `MIR_E_OWNERSHIP` aliasing). The stdlib is frozen: no reshaping of `yaml.ms` (coordinator, 2026-11-23).

## Problem

`ms build --build-type Debug` of a program calling `@std/data/yaml.ms` `parse`; frame objects of `quoted.body` (`MS_WIDE_LEAVES=4` IR, `opt default<O2>`, `llc -O2`):

| Part | Count | Bytes |
| --- | --- | --- |
| `Flow` cells (`cell0`, `cell1`) | 2 | 1040 |
| `y<n>_<k>` call argument copies (16 B) and `s<n>` result areas (24 B) | 19 and 15 | 304 and 360 |
| other cells and allocas | 6 | 160 |
| spill slots | about 62 | about 500 |

- The per-call temporaries are five inlined error-message f-strings (`y46_*`, `y518_*`, `y538_*`, `y539_*`, `y541_*`: four copies and two int-format areas each). The five sites are on different paths, so one set could serve all five.
- MIR of `quoted` after `--opt` (`ms emit <file> --opt`): `%1 = take Flow %0`, five `type.set Flow.pos`, eight `move Flow` block parameters (`b17(%117: move Flow)` ...), seven `slot Flow` temporaries (`put %2, %118; %120 = take Flow %2`) and six `put %0, %v` before exits. The record is copied through the slots and block parameters, each a 520 B cell.
- Spills (hypothesis, measured in stage 3): 624 of 6035 SSA values in `quoted.body` are used outside their defining block (211 `getelementptr`, 141 `load`, 122 `select`, 81 `icmp`); the selects and compares come from the inlined small-string equality at each `c == quote`.

## Design

1. Temporaries: the emitter's pool (`emit_slot_pool`) shares one-block slots by rank. Give argument copies and result areas the same sharing through `mir_cell_conflicts` liveness, so any two never live together share a cell. A temporary whose address the callee keeps (`mir_extern_pins_argument`, a view result) stays unshared.
2. Put-take forwarding (`opt_simplify_put_takes`): today only pure instructions may sit between `put S,v` and `r = take S`. Allow any instruction when no instruction other than a put or take names `S`. Measured alone: `slot Flow` in `quoted` 7 to 2, frame 2488 to 2472 B, so it only enables stage 2.
3. In-place record: for `x = take T p` with `p` a `var` parameter pointer, every use of `x` and of values derived from it by `type.set` and block parameters is rewritten: `type.get T.f` loads `p + offset(f)`, `type.set T.f x, y` stores `y` at `p + offset(f)`, the `put p, x'` before an exit is deleted, and a by-value use (call argument, return) takes `T` from `p` at that point.
   - Faults are well defined: `p` always holds a valid record. A scalar store is one instruction; an owning field is dropped and stored by one `type.set` with no fault point between. A fault or cancel mid-chain leaves the caller's record valid with some fields updated, as for `flow.pos += 1` written field by field. Today the record is moved out of `p` and `p` is invalid until the `put`; this is strictly more defined.
   - Unwind: a take from a caller-owned `var` pointer is `from_caller` (`mir_unwind_own.c:106`) and is not dropped on unwind. After the rewrite no owned value exists, so unwind has nothing to add; `mir_unwind_cells.c:131` must treat the rewritten loads and stores as plain memory. The verifier (`mir_verify_own.c`) runs after the pass.
   - Skipped when `p` can alias another use (a second `var` pointer to the same record, a call that receives `p` and is not rewritten) or when any use of the chain is outside the forms above. The test is the use list, never a type name.
4. Spills: measure first (live ranges across `msrt_string_clone` calls, the inlined small-string compare), then decide; no design until the cause is shown.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/emit/emit_frame*.c`, `src/compiler/mir/mir_slot_scope.c` | share call temporaries by liveness | frames of yaml `quoted`, toml `string_value`; e2e sweep |
| `src/compiler/opt/opt_simplify_mutate.c` | put-take forwarding across effects for a private slot | MIR fixture; e2e |
| `src/compiler/opt/` new `opt_fieldview.c` | stage 2 rewrite | MIR fixtures; a fault and a cancel mid-chain keep a valid record |
| `src/compiler/mir/mir_unwind_cells.c`, `mir_verify_own.c` | accept the rewritten forms | `ms check`, drop-count fixture |
| `bench/perf/` | before/after yaml and toml parsers | dated result |

## Alternatives

- Do nothing: Debug-only frames and the 20000-deep TOML test passes. Rejected by the owner's target.
- Reshape `yaml.ms`: rejected (stdlib frozen; a source workaround for a compiler cost).
- Hold fewer values (`wide_leaves` tuning): measured, two cells are the minimum for a chain plus a callee result.
- Copy-on-write records: a runtime representation change for a Debug frame problem.

## Stages

1. Share call temporaries (about -450 B). Check: frames of `quoted`, `flow_value`, toml; e2e sweep.
2. Put-take forwarding with the in-place record (forwarding alone moves nothing). Check: `quoted` below 1.5 KB; fault, cancel and drop-count fixtures.
3. Spills, once the measurement shows a cause.
