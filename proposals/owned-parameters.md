# Owned parameters for consumed arguments

## Summary

- Problem: a function that consumes a parameter (stores it, returns it, moves a match payload out of it) receives it borrowed and deep-copies it, while the caller drops its own value right after the call. Rebuilding a structure through such a function is quadratic, in Release too.
- Change: lower a parameter the ownership pass already marks `Consume` as an owned parameter (`Mode::Own`), and pass it by move when the argument is at its last use. No source syntax changes.
- Cost: a second lowered entry per function with a consumed parameter, used by direct calls; the existing borrowed entry stays for indirect calls.
- Decision requested: build stage 1 and gate it on the measurements below.

## Status

Proposal, 2026-10-27, checked against main `7fd67983`. Driven by #1650. Project direction: "getting perf back to rust level" (Chinmay, 2026-10-27).

Skeptical review: see the Review note at the end.

Stage 1 prototype, 2026-10-27: parameters inferred Consume are owned at direct calls (part A), and `alt.take`/`alt.release` move payloads out of a dying scrutinee (part B, `copyelim::run_takes`). BST insert at n=40000 takes 0.023s in Release and 0.017s in Debug (was 90s+ in both); `wrap` is linear in both. `cargo test --workspace`, conform, leak-check and e2e pass.

## Problem

Measured on main with `ms build --build-type Release`.

| Program | n = 10k / 20k / 40k | Rust |
| --- | --- | --- |
| Functional BST `insert` (below) | 0.72 s / 4.2 s / 22.6 s | O(n log n), milliseconds |
| `nd = wrap(nd, i)` where `wrap` is too big to inline | 1.8 s / 7.4 s / 33 s | linear |

```manuscript
type Tree:
    case Leaf
    case Node(l: Tree, v: Int, r: Tree)

def insert(t: Tree, x: Int) -> Tree:
    match t:
        case Leaf: return Node(Leaf, x, Leaf)
        case Node(l, v, r):
            if x < v: return Node(insert(l, x), v, r)
            return Node(l, v, insert(r, x))
```

- Verified: the ownership pass infers `Consume` for such parameters (`crates/ms-check/src/ownership/walk.rs:173-190`, `ParamMode::Consume`, exposed as `facts.parameters`), and `OWNERSHIP.md` says a payload moved out of a parameter makes the scrutinee consume it.
- Verified (throwaway test over `ms_check::check` + `hir.ownership()`): `insert` has `parameters == [Consume, Borrow]` and `wrap` has `[Consume, Borrow]`.
- Verified: lowering never reads those facts. `crates/ms-lower/src/func.rs:204-207` declares every parameter `Mode::Borrow`; the only ownership fact lowering reads is the arm bindings (`matching.rs:181`).
- Verified (`ms emit`, `insert`): the callee has no `copy %0`. The copies are inside the match: `%7 = copy (alt.get Tree.Node.l %0)` and `%10 = copy (alt.get Tree.Node.r %0)` bind the payloads (`matching.rs:196-212` binds with `own: false`), and the result construction copies again (`%13 = copy %10`, `%15 = copy %7`). Each is O(subtree), so one insert is O(n).
- Verified (`ms emit`, `wrap`): the callee copies the parameter (`%2 = copy %0`) and the caller drops its own value after the call.
- Release hides the `wrap` cost only when `inline` removes the call; the recursive `insert` is never inlined.
- Source workaround: `var` works for `wrap`-style code. It does not work for the tree: `var l`/`var r` from payloads are rejected ("only borrows from `t`"), so a functional recursive tree has no source-level fix. That is the motivation.
- Non-goals: strings and views (`two-word-string.md`), closures and interface calls, `var` parameters (already moved in and returned), changing the checker.

## Design

Two parts. Neither adds syntax. Part A alone fixes `wrap`; the tree needs A and B.

**A. Owned parameters.** For a parameter whose inferred mode is `Consume`, the direct-call entry takes it as `Mode::Own`.
- Caller, argument at its last use: pass it and emit no drop (the `drop %7` after the call). The facts exist (`Use { access: Move, last }`) but no lowering code consumes them yet; stage 1 adds that consumer.
- Caller, argument not at its last use, or a borrowed place: emit `copy` and pass the copy. Same cost as today, moved from callee to caller.
- Indirect callers (closure values, interface dispatch, `Callable` arguments, natives) keep the borrowed signature. A function with a consumed parameter keeps its borrowed entry as a wrapper that copies and calls the owned entry.
- Callee: the parameter is an owned local; the `copy` at the consuming position disappears.

**B. Move-out of an owned scrutinee.** When `match t:` scrutinizes an owned value at its last use (`consumed_scrutinees`, already computed by the checker), payloads that are moved out bind by move instead of `copy (alt.get ...)`, and the construction `Node(insert(l, x), v, r)` moves `r` instead of copying it.
- The remainder of the scrutinee must be dropped per field: the payloads not moved on the taken path, and payloads moved on different paths. The nearest existing piece is MIR `alt.unbox`, which `copyelim.rs:879` produces only for dead sources.
- A cheaper first step, without signatures: a MIR rewrite that turns `copy (alt.get f %s)` into a move when `%s` is owned and dead afterwards. It needs A to make `%0` owned.

Before and after for `wrap`:

```text
before                                   after
main: call @wrap(%7, %6); drop %7        main: call @wrap.own(%7, %6)
wrap: %2 = copy %0; list.lit %2          wrap.own(own %0): list.lit %0
```

Edge cases, one each:
- Recursion: `insert(l, x)` passes the payload `l`, owned after B, so it is passed by move and each level does O(1) work besides the recursive call.
- Cleanup and faults: an owned parameter is dropped on every exit path; `ms-mir/src/unwind.rs` tracks `Mode::Own` parameters.
- Default arguments (`call.rs`): evaluated in the caller, owned, passed by move.
- Generics: the mode is per instantiation (`instance_key`); stage 2.
- Entry points: test blocks and `main` keep the borrowed entry only.

## Unproven (found in review, to be settled by the stage 1 prototype)

- No source function has been lowered with an `Own` parameter. `Mode::Own` function parameters appear only in internal helpers (`unwind.rs:242,290`); `verify.rs:226-232` rejects owned parameters on `Closure` and `Method` functions; `ms-clif` has no `Mode::` references.
- `function_for` returns one `FuncId` per `instance_key` and has about 15 callers (`iface.rs`, `fixture.rs`, `text.rs`, `mathops.rs`, `json.rs`, `scope.rs`, `function_lent`) that assume the borrowed signature; the owned entry needs its own key and queue slot, and the `$lent` variant doubles.
- `noalias` and `var_positions` are indexed by parameter position.
- `inline`, `copyelim` (`:145`) and `lastuse` (`:243`) special-case owned parameters; their interaction is unanalysed.
- No "compiler-generated wrapper" flag exists on `Func` for fault traces.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-lower/src/func.rs` | `function_for` creates the owned entry and the borrowed wrapper from `facts.parameters` | MIR snapshot for `wrap` and `insert` |
| `crates/ms-lower/src/call.rs` | direct calls pick the entry and the move/copy per argument from `Use.last` (new consumer of the facts) | e2e: BST and `wrap` scaling, aliasing fixtures |
| `crates/ms-lower/src/matching.rs` | part B: move payloads out of an owned last-use scrutinee | MIR snapshot, leak-check |
| `crates/ms-mir` | owned parameters on Normal functions (verify, unwind, interp); `Func` flag for generated wrappers | `ms-mir` interp test for an owned parameter |
| `crates/ms-clif` | confirm aggregates pass the same way for `Own` and `Borrow`; drop at return | `cargo test -p ms-clif` |
| `crates/ms-check` | unchanged | existing `tests/ownership.rs` |
| Fault traces, debugger line tables | wrapper marked generated | trace test with an indirect call |
| `stdlib`, `bindings.json`, formatter, lint, LSP, docs | unchanged; add a scaling note in `documentation/` performance pages | docs check |

## Alternatives

| Option | Verdict |
| --- | --- |
| Do nothing | BST insert and any rebuild-through-a-function loop stay O(n²) per operation chain; users must know to write `var`. The measurement above is the evidence. |
| More inlining | Cannot cover recursive or large callees (`insert` is recursive); the second table row is a non-inlinable `wrap`. |
| Only a MIR pass making `copy (alt.get ..)` a move when the scrutinee is dead | Cheapest, but the scrutinee is a borrowed parameter until part A makes it owned. Kept as the first step of B. |
| Owned entry for direct recursion only | Avoids wrapper plumbing at the 15 `function_for` call sites; covers `insert` but not `wrap` across functions. Candidate for stage 1 if the general plumbing is too large. |
| Dynamic uniqueness flag (callee steals when the caller's value is dead) | Adds a runtime flag and branch to every call and a hidden protocol between caller and callee; the static fact already exists. |
| Change the checker to require `.clone()` on consumed parameters | Breaks working programs and moves the cost to users without removing it. |
| Reference-counted or copy-on-write values | Contradicts DESIGN.md decision 1 (no reference counting for ordinary data). |
| Owned entry for every function | Doubles code size for no gain; restrict to functions with a `Consume` parameter. |

Drawbacks of the chosen design: more functions in the module for consuming functions; one extra frame candidate in traces, handled by marking the wrapper.

## Staging and verification

1. Prototype A for direct recursion only (owned entry used by self-calls) plus B's MIR rewrite. Gate: BST insert at n = 40k under 1 s, leak-check and `make conform` green. This also settles the Unproven list for `Own` parameters in verify, unwind and clif.
2. General A: owned entry for any direct call, borrowed wrapper for indirect calls, generics, default arguments, consumed receivers. Gate: `cargo nextest run --workspace`, `make conform`, `make leak-check`, `make e2e`; `wrap` row linear; `bench/perf` no regression with a dated section added.
3. Add the scaling fixtures (n = 20k and 40k within a time bound) to `tests/e2e/testdata`.

Go/no-go: if stage 1 does not bring BST insert to O(n log n), stop and record why here.

## Open questions

- None that change the language or user-visible behavior. Receivers that are consumed (`facts.receiver`) are included in stage 2.

## Review note

Skeptical review (a fresh reviewer given only this file, 2026-10-27): verdict revise. The `wrap` cost is a callee copy, but the BST cost is the payload-binding and construction copies, which owned parameters alone do not remove; stage 1 as first written was unachievable and lowering had no consumer for the ownership facts. This revision re-roots the problem on the payload copies (re-verified in `ms emit`), adds part B, lists the unproven mechanisms, and starts with a recursion-only prototype. A second review is needed on the revised design before stage 2.
