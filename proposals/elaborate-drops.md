# Elaborate drops on MIR

## Summary

- Problem: `ms-lower` places every scope-end and early-exit drop while it generates code, and tracks "this path already emitted the drop" itself (`closed_on_path` 22 uses, `scope_done`, `rest_closers`, `hidden_closers`). The MIR verifier then proves exactly-once ownership after the fact. Each new construct that moves or closes a value must repeat the bookkeeping.
- Change: lowering emits a Raw phase of MIR with scope markers and no scope-end drops; one `elaborate` pass places them from move-state dataflow; the existing verifier runs on its output.
- Decision requested: build stage 0 (prototype of the failed close) and stage 1; if resources cannot move into the pass, stop after stage 1.

## Status

Proposal, 2026-11-11, checked at `832ea3d3`. Stage 0 result (`crates/ms-mir/src/elaborate.rs`, `tests/elaborate.rs`): on hand-written Raw MIR, nested closing resources with first-error-wins (all four fail/succeed combinations) and an arm that consumes the scrutinee both elaborate to verifying MIR with the expected close order and no per-path state. Also covered on hand-written Raw MIR: drop flags for `MaybeMoved` owners (`move.out` plus a flag block parameter, `drop.if` or a guarded close), loops with `break`/`continue` ending scopes, `cleanup.push` at `own` with the discard at close or move, and `alt.take` then `alt.release`. Not covered yet: `try`, a real error type (errors are ints), markers as real ops, exits that leave scopes without an explicit `raw_end`, and partial moves that differ between paths into a join (rejected with an error). Owner direction: "having a separate pass will keep future bugs out, don't over index on existing code, we're setting things up for future". A skeptic review found the first draft under-evidenced; a second review (Fable) chose the design below: one pass owning all scope-exit cleanup, resources included. Step 5 option (ii) of `compiler-stage-layering.md`; a checker drop plan was rejected there (the set is emission state, partly per-instance).

Stage 1 result: `scope.begin/own/end` are real ops (`verify::is_raw` marks a function Raw; the verifier skips its ownership check until `elaborate` runs after `drain`). Lowering hands the pass the immutable, never-moved, closer-free locals (`own_raw`); the conformance corpus, leak, count, resource, close and copy checks are unchanged. Open-question probes (2026-11-11): the early scrutinee drop needs a marker handing the scrutinee to the arm scope (fallthrough closes it before arm locals, `return` after); `list_iters` rest release is a runtime-index partial owner the three move states cannot express; `Split` needs field-path owners, and `own` must not rely on `needs_drop` (an all-scalar resource in a split record fails `move.out` today, unfiled); `defer_close_failures` and plain-fault unwinding fit.

Stage 2 result: single-definition locals are Raw-owned whether or not they move; the pass supplies the drop flags, so lowering's optional box and `held` flag are skipped for them, and a returned value leaves its owner (`scope.disown`) before the scopes end. `var` locals (a `scope.own` at each store) are not in yet: `tools/e2e.ms` `main` (a `var` list filled in a loop in one branch of an `if`, with the iterable `given` moved into the loop on that branch only) then fails verification with "owned values differ between incoming edges" at the loop join, a drop-flag and loop-phi interaction in the extended pass still to be isolated. Stage 3 (resources) is untouched.

## Problem

- Verified: `verify.rs` already states the rule (live set identical on every edge, empty at `ret`), so the target of placement is fully defined; lowering still re-derives it at about 130 `drop_value`/`drop_local`/`Op::Drop` sites.
- Verified: the writers of `closed_on_path` are emission state: arms that took a scrutinee's payloads (gated by `borrowed_case`, a monomorphic variant property, `matching.rs:234-365`), a failed-close return with no `NodeId` (`close.rs:1693`), a `try` moving a named local's error out (`matching.rs:600`), a returned interface view (`expr.rs:449`).
- Not established: which closed issues elaborate would have prevented. Classified by title only (hypothesis): #3075, #3078, #3086, #2883 are close and move semantics of natives and Optionals, and the seven "implicit copies of a borrow" issues are copies, so none is clearly a scope-end placement bug.
- Hypothesis: a new exit shape (a construct that leaves a scope) is where drop bugs recur; the 11 closed issues in `compiler-stage-layering.md` are that shape. No row fails today.

## Design

- **Raw phase.** `Module.phase: Raw | Elaborated`. Raw MIR may leave an owned value live at `ret` and at edges out of a scope; the verifier's end-state rule is checked only on Elaborated MIR. Raw still checks types, dominance, and "no value consumed twice".
- **Markers.** `scope.begin S`, `scope.end S`, and `own p, S, policy`: `p` is an owner place (a builder variable or slot, not an SSA value, because locals are reassigned and `T?`-boxed). `policy` is the only checker input: `Drop | Close{Propagate | Discard | Fault}`, from facts lowering already reads (`CloseHandled`, `closer.explicit`, `close.rs:1430-1460`). Early exits (`return`, `break`, `continue`, `try`) are plain edges; the pass finds the scopes they leave from the marker nesting. Markers are removed by `elaborate`.
- **Move state, only in the pass.** Per owner `Live | Moved | MaybeMoved`, computed from consuming ops (`arg_modes`, `take`, `put`, `opt_unbox`); drop flags are born here. `ownership/moved.rs` then has no lowering consumer and goes, so the fact has one producer.
- **Fallible close as an exit edge.** The documented rule (`closeable.md:72-77`) is first error wins over the scopes an exit leaves: per exit the pass emits `r = close p; outcome = outcome.is_error ? outcome : r`. A failed close at fallthrough branches to a return edge the pass elaborates for the outer scopes, with the closed owner `Moved`. This removes the re-entrant `emit_return`, the `closed_on_path` snapshot and `returning_close_error`. No glue function: glue carrying `pending_return` would hide control flow from the verifier.
- **Cleanup stack.** The pass emits `cleanup.push` at `own` and the discard at the elaborated close or move for `Close` owners, replacing the hand pairing in `close.rs:390-420` and `1485-1510`. Merging this with `unwind.rs` liveness registration comes last, if at all.
- **Not changed: infallible implicit close.** Users would silently lose close errors, and `scopes.md:51` and `closeable.md:72` promise the opposite. If stage 0 fails, the fallback is "implicit close failure always faults", never "discard"; that is user-visible and needs the owner.
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

0. **Prototype on hand-written Raw MIR:** (a) a payload-taking match arm with an early `return` (the `matching.rs:234-365` shape); (b) two nested resources, a failed close at fallthrough plus a failed close under a pending domain error (`close_error_precedence.ms`). Stop if the precedence test needs per-path state from lowering or a per-arm "partially moved" marker.
1. **Shadow, test-only.** Oracle: the verifier on elaborated output plus the close and resource matrices; a drop diff is triage only, and any unexplained difference is a finding.
2. **Named memory locals.**
3. **Named resources.** `closed_on_path` and `scope_done` reach zero here (29 references today). Kill criterion: if resources cannot move, stop after stage 1.
4. **Temporaries** (`resource_temps`), then cleanup-stack unification.
Gates each stage: conformance, `tests/ownership-counts`, resource and close matrices, `cancel-sweep`, `leak-check`, copy-check zero; compile time within 2%.

Thresholds, set before measuring: `closed_on_path`, `scope_done`, `rest_closers`, `hidden_closers` reach 0 by stage 3; `ms build` time on `bench/perf` compile cases regresses by at most 2%; emitted MIR size does not grow on the corpus; no row of any matrix changes.

## Open questions

- Unverified: the early scrutinee drop in a match arm (`matching.rs:337-347`) and `list_iters` rest release (`func.rs:1363-1375`) may need their own scope markers to keep close order; `Split` per-field flags (`OWNERSHIP.md:28`) may need field-level owners; `defer_close_failures` (`close.rs:~1537`) is a second failure convention `policy` must cover; whether `unwind.rs` covers plain faults.
- Drop flags stay runtime values first; measure before cloning exit paths.
