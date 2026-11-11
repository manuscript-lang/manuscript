# Elaborate drops on MIR

## Summary

- Problem: `ms-lower` places every scope-end and early-exit drop while it generates code, and tracks "this path already emitted the drop" itself (`closed_on_path` 22 uses, `scope_done`, `rest_closers`, `hidden_closers`). The MIR verifier then proves exactly-once ownership after the fact. Each new construct that moves or closes a value must repeat the bookkeeping.
- Change: lowering emits a Raw phase of MIR with scope markers and no scope-end drops; one `elaborate` pass places them from move-state dataflow; the existing verifier runs on its output.
- Decision requested: build stage 0 (a prototype of the hardest case) and stage 1; resources stay in lowering unless stage 0 shows glue can carry them.

## Status

Proposal, 2026-11-11, checked at `832ea3d3`. Owner direction: "having a separate pass will keep future bugs out, don't over index on existing code, we're setting things up for future". Skeptic review (2026-11-11) found the first draft under-evidenced; this version narrows scope to memory values and adds a prototype gate. Step 5 option (ii) of `compiler-stage-layering.md`; a checker drop plan was rejected there (the set is emission state, partly per-instance).

## Problem

- Verified: `verify.rs` already states the rule (live set identical on every edge, empty at `ret`), so the target of placement is fully defined; lowering still re-derives it at about 130 `drop_value`/`drop_local`/`Op::Drop` sites.
- Verified: the writers of `closed_on_path` are emission state: arms that took a scrutinee's payloads (gated by `borrowed_case`, a monomorphic variant property, `matching.rs:234-365`), a failed-close return with no `NodeId` (`close.rs:1693`), a `try` moving a named local's error out (`matching.rs:600`), a returned interface view (`expr.rs:449`).
- Not established: which closed issues elaborate would have prevented. Classified by title only (hypothesis): #3075, #3078, #3086, #2883 are close and move semantics of natives and Optionals, and the seven "implicit copies of a borrow" issues are copies, so none is clearly a scope-end placement bug.
- Hypothesis: a new exit shape (a construct that leaves a scope) is where drop bugs recur; the 11 closed issues in `compiler-stage-layering.md` are that shape. No row fails today.

## Design

- **Raw phase.** `Module.phase: Raw | Elaborated`. Raw MIR may leave an owned value live at `ret` and at edges out of a scope; the verifier's end-state rule is checked only on Elaborated MIR. Raw still checks types, dominance, and "no value consumed twice".
- **Markers.** `scope.begin S`, `scope.end S`, and `own v, S` (value `v`, owned, belongs to scope `S`). Early exits (`return`, `break`, `continue`, `try`) are plain edges; the pass finds the scopes they leave from the marker nesting. Markers are zero-cost and removed by `elaborate`.
- **`elaborate`.** Forward dataflow over owned values: states `Live | Moved | MaybeMoved`. At each edge leaving a scope it inserts, in reverse `own` order: nothing for `Moved`, `Drop` for `Live`, `DropIf` on a flag it also introduces for `MaybeMoved`. Drop flags stop being a lowering choice.
- **Scope of the first version: memory values.** Resources keep lowering's closers, the runtime cleanup stack (`hold_resource_temp`, `msrt_cleanup_*`, `closer.flag`) and failed-close returns (`close.rs:1485-1700`), because a scope-end close is control flow that re-enters `emit_return` with pending state, and registration happens at the owner's definition, not at the drop. They move to the pass only if stage 0 shows a glue signature that carries `pending_return` and the outer drops.
- **Dataflow domain.** Locals are builder variables, some in memory slots (`Local.slot`), some `T?` boxes (`Local.opt`, a move leaves `none`), some guarded by `held`/`closer.flag`. The pass tracks per-owner state `Live | Moved | MaybeMoved` where a move is the op that consumes the value (`take`, `put`, `opt_unbox`, consuming operand positions from `arg_modes`); slots and opt boxes are tracked as one owner each. State that depends on runtime flags (`split`, `hidden_closers`, entry flags) is out of scope.
- **Cancellation.** `unwind.rs` keeps cancellation release and consumes the elaborated drops.
- **Interaction.** `lastuse`/`copyelim` run after `elaborate` and stay optimizations. The verifier runs on Raw (partial) and on Elaborated (full) output in debug builds.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-mir/src/ir` | `phase`, three marker ops, text form in `print`/`parse` | parse/print round trip |
| `ms-mir/src/verify` | Raw rules, Elaborated rules | verifier unit tests, one reject case per rule |
| `ms-mir/src/opt/elaborate.rs` (new) | the pass | per-shape unit tests, resource and close matrices |
| `ms-lower` | emit markers, delete scope-end drops and `closed_on_path` | ledger in `stages.rs` reaches 0 |
| `ms-build` | run `elaborate` before `unwind` | conformance run/test phases |

## Alternatives

- Do nothing: no row fails; every new exit shape needs hand bookkeeping in about 130 sites. This is the baseline the stages must beat on lines deleted and on the ledger.
- Checker drop plan on the tree (`compiler-stage-layering.md` 4b): rejected, it cannot name per-instance emission state and would add a second source of the same fact.
- Rust-style generic MIR: rejected in the same proposal (a fourth IR).

## Stages

0. **Prototype.** Elaborate one hard case end to end on a copy: a named memory local and a payload-taking match arm with an early `return` and a later `try` (the `matching.rs:234-365` shape). Stop if it needs a marker that says "partially moved" per arm decided by lowering; that means lowering still decides moves and only half the bookkeeping moves.
1. **Shadow, test-only.** Lowering emits markers beside today's drops; `elaborate` runs on a copy; a test compares its drops with lowering's per exit over the corpus. Differences are classified into a fixed list before comparing (flag-guarded, resource, partial move, order only); stop if more than 5% of exits fall outside the first category plus order-only.
2. **Named locals without glue** (memory values): lowering stops emitting their scope-end drops. Gate: conformance, `tests/ownership-counts`, resource and close matrices unchanged.
3. **Temporaries and `pending_return`.** Same gate.
4. **Resources via glue**, only if stage 0 allows it; otherwise they stay and the ledger keeps its resource-only identifiers. Gate: matrices, cancel-sweep, leak-check, copy-check zero. `cancel-sweep` also gates stage 2, because `unwind.rs` registers by liveness and must see the same shape.

Thresholds, set before measuring: the memory-value uses of `closed_on_path` and `scope_done` reach 0 by stage 3 (the resource ones by stage 4 or never); `ms build` time on `bench/perf` compile cases regresses by at most 2%; emitted MIR size does not grow on the corpus; no row of any matrix changes.

## Open questions

- Do per-scope drop flags stay runtime values, or does `elaborate` prefer cloning the exit path? Recommendation: flags first, measure.
