# MIR owns stack-slot lifetimes; backends only emit

## Summary

- Problem: three places guess what may point into a stack slot (`lastuse` in MIR, `slotshare.rs` for Cranelift, `llvm_lifetimes.rs` text scan for LLVM). Two of them assume safe unless a name list says otherwise, which is how #4284 (LLVM reused a slot a split view pointed into) shipped.
- Change: MIR says which slots are statement-scoped and proves it in the verifier; both backends translate that fact and scan nothing. Runtime effects (`fresh`/`borrows`) become declared for every aliasing-capable function, not opt-in.
- Decision requested: approve the order of stages below.

## Status

Proposal, 2026-11-16, checked against `a4f4a88f`. `lastuse` is already a MIR pass and no backend computes last use. Direction (Chinmay, 2026-11-16): "move language specific things in mir or in higher layers and keep backends for lowering and machine code". `lastuse` is already a MIR pass (`ms-mir/src/opt/lastuse.rs`); this extends the same idea to slot lifetimes.

## Problem

- LLVM: `llvm_lifetimes::mark` classifies every `alloca` by scanning IR text. A pointer passed to a call is harmless unless the callee is one of four names (`RETAINS`). A runtime function whose result points into its argument is only known through the opt-in `// ms: borrows` flag; one function has it (`msrt_string_view_bytes`), six more are matched by name (`rtcall.rs`, `ViewResult`).
- Cranelift: `slotshare::share` runs its own scan over `temps` with its own rules.
- Repro of the class: `text.split(sep)` read in place writes its pieces into a slot; LLVM ended the slot at the block, the list still pointed into it, the first piece read `:` (#4284, fixed for split only by #4285). 40 corpus fixtures fail under `MS_POISON_SLOTS=1` on the commit before the fix, about 14 without it.
- About 115 to 135 runtime functions (the count depends on how handle parameters are filtered) take a pointer and write a `String` or `VecVal` out-parameter without `@fresh`; most are fresh (concat, copy, crypto), but five views are unflagged and unlisted today: `msrt_string_view`, the three `trim_*_view`, `msrt_bytes_view`. A view of an inline text points into the argument's own slot.
- Cranelift is laxer than LLVM: `slotshare` accepts any call, with no retain list, so the two scanners already disagree. More deciders than the two scans: `feeds_view_result` and `bind_early` (`mir_llvm/types.rs`), `spill` vs `spill_pinned` keyed on `BorrowsArgument` in both backends, `Module::result_views`, `copyelim`, `loopslot`.

## Design

- **Effects are declared.** Every runtime function with a pointer parameter and a `StrVal`/`VecVal` result declares `fresh` (result borrows nothing) or `borrows`. `cargo xtask symbols` fails on an undeclared one. `ExternRole::ViewResult` and `BorrowsArgument` come from the flag; the name list goes.
- **`slot.temp`.** A new MIR op beside `slot`: its address is valid to the end of the block that defines it. `slot` stays frame-lifetime. Lowering still emits `slot`; a MIR pass `slotscope` rewrites a `slot` to `slot.temp` when the rules hold, so lowering carries no new decision.
- **Verifier rule for `slot.temp s` in block B** (the invariant the backends rely on):
  - an address derived from `s` (`ptr.add`, `list.addr`, projections) is used only in B and is never stored, returned, captured, or passed as a block argument;
  - a call may take it only if the callee neither keeps pointers (the declared `keeps`/`spawns` effects) nor returns one; the rule is only as sound as that declaration, which stage 1 makes mandatory;
  - the result of a `borrows`/view call over it is a *view of s*: B-local, and rejected if it is stored, returned or passed as a block argument. For an inline text the view points into the slot, so "view of s" follows `load`, `put` and block arguments of the view value, not only addresses.
- `loopslot` and other entry-block slots are never rewritten to `slot.temp`; a cleanup or unwind handler counts as outside B.
- **Backends.** Cranelift shares `slot.temp` storage by block rank (today's algorithm, no scan). LLVM starts the lifetime at the op and ends it at the end of B. A `slot` or an unproven one is never shared or ended early.
- **Spills.** By-value arguments marshalled to pointer parameters, and out-parameters, are created by the backends today (4 Cranelift `temp_slot` sites, 23 LLVM `alloca` sites, 6 pinned). Lowering emits them as MIR slots instead, so the same pass classifies them.
- **Poison.** `MS_POISON_SLOTS` (PR #4288) moves to one MIR pass that appends a `fill` at the end of B for each `slot.temp`; backends lower `fill` only. The MIR interpreter fills too.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-rt`, `xtask` | declare `fresh`/`borrows`/`keeps` on every aliasing-capable function; check | `cargo xtask symbols`; new test that an undeclared aliasing signature fails |
| `ms-mir` | `slot.temp`, `fill`, `slotscope` pass, verifier rule, text format, interpreter | verifier accept and reject cases; `parse`/`print` round trip |
| `ms-lower` | explicit spill slots; roles from the flag | `ms emit` golden for a view call |
| `ms-clif` | `slot.temp` shares storage; delete `slotshare.rs` scan | corpus; frame size of the recursive-parser fixtures unchanged |
| `ms-mir-llvm` | markers from `slot.temp`; delete `llvm_lifetimes.rs` scan | LLVM corpus; `drift-check`; poison corpus |

## Alternatives

- Do nothing: each new view-returning runtime function is unsafe until someone remembers a flag; #4250 only surfaced on a main run.
- Keep both scanners but invert the default to an allowlist: smallest change, still two scanners that must agree and still no verifier proof.
- Pin every slot: removes the class, loses stack coloring (a recursive parser would pay kilobytes per call, the reason the markers exist). Measure before choosing it; do not assume.

## Stages

Review (independent subagent, 2026-11-16) found the original order unsafe and the evidence for `slot.temp` thin, so the first stage stands alone and `slot.temp` waits for its gate.

1. Declare effects (`fresh`/`borrows`/`keeps`); drive `ViewResult`, `BorrowsArgument` and both backends' retain checks from them, so `slotshare` and `llvm_lifetimes` read one table; flag the five unflagged views. Fixes the two-scanner disagreement. Gate: `make verify`, LLVM and Cranelift corpus, poison corpus.
2. Spills become explicit MIR slots, so one pass sees them. Gate: instruction counts in `bench/perf/counts.txt` within 1%, corpus.
3. Go or no-go on `slot.temp`: measure frame size of the recursive-parser fixtures with every slot pinned. Pinning is chosen if the cost is under 5%; otherwise build `slot.temp`, `slotscope` and the verifier rule, delete both scans, and make poison one MIR `fill`.

## Open questions

- Should drops decided in lowering move into MIR too? `ms-lower` still emits scope-end drops (`drop_scope_locals`), temporary drops (`close_temp`, `drop_unused`) and `DropIf` for conditional or reassigned owners; `lastuse` and the cancel redesign then adjust them. Chinmay earlier let temporaries and locals stay in lowering, and the cancel redesign does not need the move. Moving them follows the newer direction (language behavior in MIR, backends only emit) and would leave one place that decides when a value dies. Recommendation: yes, as its own stage after stage 3, local drops first. Not started; needs Chinmay's OK.
