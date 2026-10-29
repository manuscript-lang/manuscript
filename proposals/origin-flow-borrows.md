# Origin flow: one rule for every value that holds a borrow

## Summary

- Problem: a borrow is tracked two ways. A local binding of a call result holds its sources (`Meta.origins`, `Borrow`). Every other flow (move, clone, field, closure capture, collection, wrapper) is banned by a type-level predicate (`borrows(ty)`) or patched case by case. The skeptic review of #1908 to #1917 found six accepted use-after-free programs, all from a derivation that forgot to pass the hold along.
- Change: every expression of a borrowing type gets an origin set from one dataflow rule. A holder keeps its sources unchanged until its last use (the existing check). Moves, clones, projections, `some(it)`, closure captures and local containers pass origins along instead of being banned.
- Cost: `ms-check/ownership` only (`walk.rs`, `modes.rs`, `classify.rs`, `mod.rs`); no syntax, MIR or runtime change. Net deletion of special cases.
- Not solved: storing a borrow into storage the caller owns (a `var` parameter, a field of a parameter) needs a summary effect, the lifetime-parameter problem. It stays one rejected case.
- Decision requested: approve replacing the carrier special cases with origin flow, accepting that some programs become accepted that are rejected today.

## Status

Proposal, 2026-10-29, against `main` at `1d2e53a1` plus #1922. Direction (Chinmay): "can realistically assess ref outlives the source? if yes then the general ownership checks should have, having these gotcha rules makes things more complicated." Extends `borrowing-iterators.md`.

**Outcome of skeptic review: do not build R4 or the `origins_of` rewrite. Stage 1 only (below). Review findings are in the Review section.**

## Problem

- Today a borrowing value is handled by rules keyed on its type, not on where it came from. Verified with `grep` on `crates/ms-check/src`: 48 references to `borrows(`, `with_held`, `carrier_move`, `carrier_clone`, `movable_carrier`, `cloned_carrier_origins`, `through_ref`, `HeldReceiver` and `HeldParam`.
- Each new flow needed its own flag. #1922 added `carrier_move` and `carrier_clone` so `let b = it` and `let c = it.clone()` pass one expression kind at a time; `return it`, closure capture and projection each have their own code.
- The same omission produced every confirmed hole (measured by the independent review, programs in the #1922 thread):
  - `nx(var it)` over a carrier: the result held `it`, not what `it` holds.
  - `dup(it)` cloning a carrier parameter.
  - A closure capturing a carrier, and a closure capturing that closure.
  - `Cursor(source: c.source, ..)`, `let s = c.source`, `for x in c.source`.
- Observable cost: `Optional[Cursor]`, a local `List[Cursor]` and a wrapper record holding an iterator are rejected even though the sources are all locals with a known lifetime.
- Non-goals: lifetime syntax, `ref` in function types, storing borrows in caller-owned storage, lazy adapters (`map`, `filter`).

## Design

One rule: a value that holds a borrow keeps its sources unchanged until its last use. What changes is how "holds" is computed.

**Origin set of an expression `o(e)`:**

| Expression | `o(e)` |
| --- | --- |
| a place `p` (not borrowing) | `{p}` |
| a name bound to a holder | the holder's set |
| `ref` field path of a holder | the holder's set |
| constructor | union of `o(arg)` for `ref` arguments and for arguments that are holders |
| call | for each summary slot: `o(arg)`, plus the argument holder's set (`Held` slots keep meaning "only what it holds") |
| `some(e)`, `ok(e)`, record or alternative field | `o(e)` |
| `e.clone()`, move, `let b = e` | `o(e)` |
| closure | union of the sets of what it captures |
| temporary of a non-place | `{}` (an error where a set is required) |

**Holders** are bindings of a borrowing type, closures and, new, a local aggregate that receives a holder. The three rules that exist today stay:

- R1 freeze: while a holder is live its sources cannot change, move or be reassigned (`active`/`check_change`, unchanged).
- R2 derive: any value built from a holder gets `o(e)`, so the hold survives the holder's death. This replaces `with_held`, `movable_carrier`, `cloned_carrier_origins`, `carrier_move`, `carrier_clone` and the Member-through-`ref` patch.
- R3 return: a result may be a holder only if every set member maps to a read-only parameter slot (existing `lend_slot`); the summary names those slots.

New rule R4 absorb: moving a value with a non-empty set into a local place (`its.append(it)`, `h.field = it`, `Holder(c: it)`, `some(it)`) adds the set to that place's root. The root becomes a holder. If the root is a parameter, a field of a parameter or a captured variable the rule cannot be proved, so it is the one rejected case: "cannot store a borrow in `xs`: it belongs to the caller".

Stays as is, because it is about shared storage rather than lifetime: a path through a `ref` field is read-only (#1917); a constructor `ref` argument must be a place; carriers are not `Resource`.

Deleted: the `borrows(ty)` bans on move, reassignment-by-move, clone/copy (#1914), collection storage and escaping capture; the class floor that makes a borrowing type `Move` becomes "a holder is never implicitly copied". A holder reassigned from another holder unions the sets (`it = other`).

Before and after:

```
# rejected today (`many` would hold values that hold a borrow, which a collection cannot do), accepted after
fn f(var d: Deque[String]) Int:
    let it = d.iter()
    var many: List[DequeIter[String]] = []
    many.append(it)
    d.clear()          # still an error after: `many` holds d
    return many.length()
```

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check/ownership/walk.rs` | `origins_of(expr)`; R2 and R4 replace the carrier special cases | existing `tests/ownership` corpus unchanged, plus the six holes as reject cases and the new accepts |
| `ms-check/ownership/modes.rs`, `mod.rs` | `Held` slots kept; result-borrows exemption derived from sets | corpus |
| `ms-check/ownership/classify.rs` | floor of `Move` from "holds a set" | corpus |
| `ms-check/types.rs` | `borrows` stays as the cheap "may hold" type test | unit |
| parser, MIR, lowering, codegen, runtime, stdlib | unchanged | `make verify-full` |
| docs | OWNERSHIP.md carriers bullet replaced by the rule above; loops.md loses the restriction paragraph | `make docs-check` |

## Alternatives

- Do nothing: sound after #1922 (review found no further holes), but every new feature that moves a carrier (adapters, wrapper iterators) needs another flag, and each omission is a use-after-free. Evidence: six holes in one review.
- Lifetime parameters in signatures: closes the caller-owned-storage case but is new syntax and the vision avoids it.
- Runtime check (generation counters on containers): catches the bug at the cost of a word per container and a check per borrowed read; rejected by the performance goals.
- Smallest version: keep today's rules and add the missing derivations only (#1922). Done; this proposal is for what remains.

Drawbacks: origin sets are approximate (a union), so some programs are rejected that a precise analysis would accept; the diagnostics must name the holder that causes a conflict.

## Staging and verification

1. Add the six reviewer holes and the new accepts to the corpus first; they pass or fail as today.
2. Implement `origins_of`, route R2 through it, delete `with_held` and the carrier flags; corpus stays green.
3. Implement R4 and remove the collection/field/wrapper bans; add accepts and rejects.
4. Independent skeptical review with the six programs plus new attacks; `make verify-full`.

Go/no-go: stage 2 must leave the corpus unchanged and delete more code than it adds; otherwise stop.

## Open questions

- Mutable `ref` fields (Chinmay: "can we treat ref field as mutable borrow of the source?"): a `var ref` field that holds its source exclusively and lets the carrier change it. Checking reuses the exclusive flag already in `Borrow.origins`. Runtime needs the source address rather than the shallow view (the same ABI as a `var` parameter's pointer with take and put), which is a new MIR representation. Shared `ref` stays for read-only iteration, since nested loops and several iterators over one container need shared holds. Recommendation: a later stage, after origin flow lands.
- Exclusivity and cleanup for mutable `ref` fields (Chinmay: "there can only be one, and must be dropped with closed appropriately"): at most one exclusive holder per source, already enforced by the borrow list. The hold ends at the carrier's last use and no later than scope end; locals drop in reverse order. A carrier with cleanup is a `Resource` (linear, not clonable, closed when its `let` or `var` scope ends, on every exit); its implicit close counts as a use, so its sources stay frozen until scope end. Closing a source that is a resource while a carrier is live is a change to it and is rejected.

## Review

Independent skeptic review, verified against the current binary where marked.

- Evidence is weaker than stated: about 21 of the 48 references are deletable, the same helpers #1922 added (about 130 lines in `walk.rs`). The six holes had one cause, a missing hold on derived values, already closed by `with_held`. Only three carrier types exist in stdlib and nothing uses `List[Cursor]`, `Optional[Cursor]` or adapters.
- R4 turns fail-closed type bans into fail-open dataflow and needs three things this proposal lacks:
  - A scope and drop-order rule: an outer aggregate can absorb a holder over an inner local that dies first (`many.append(d2.iter())` inside a loop), and a holder can move into an escaping task closure over a source declared later.
  - A loop fixpoint: the walker passes over loop bodies once, so a set that grows late in iteration k is unseen at the top of k+1.
  - Alias resolution: the root of a place must resolve through `MutBorrowed` aliases (`var ys = many; ys.append(it)`).
- Call effects are missing: a consumed holder argument must union into the result and into `var` arguments, and natives (`Optional.get(default: it)`) copy carriers today only because the empty-set bind check fails closed.
- R3 blocks adapters (`take(it, n)` consumes the carrier); a consume-held slot kind would be needed.
- The class floor cannot depend on flow information; it must stay type-level.
- The go/no-go gate runs at stage 2, before the risky rule is built.

Decision: stage 1 only (the six holes and new accepts as corpus cases). Reopen R4 only when a real feature needs it, as a rejection-first proposal that specifies scope, fixpoint, aliasing and call effects, with e2e tests using runtime-built long strings.
