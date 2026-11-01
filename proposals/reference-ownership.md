# Plain data copies, containers have one owner

## Summary

- Problem: ownership diagnostics are the main cause of first-build failures for agents (#2147), and the surprises sit where the model departs from the habits of Python, Go and TypeScript: `var y = xs[0]` writes through (#2168), a stored or returned string needs `.clone()` or silently makes the function consume its argument, and `if var x = m.get(k)` changes a copy with no signal (#2164).
- Change: the copy/own split follows the mutable/immutable split those languages already teach. Plain data (scalars, `String`, `Bytes`, records and alternatives of only those) copies wherever it is stored, returned or bound with `var`; containers and records holding them keep one owner, `let` borrows, `var` mutates. `if var` on an owned payload that is changed and then dropped is an error. No new syntax, no refcount, no GC, no change to `Class` or to the borrow rules.
- Decision requested: approve the rule and the stages, and the reversals listed under Open questions (visible string copies, "copies are declared, not inferred", "a returned part writes `.clone()`").

## Status

Proposal, 2026-11-01, checked against `a0f61d32`. Direction (Chinmay, 2026-11-01): "reference semantics but with ownership and borrow rules, no reference counting; numeric copied out, records and strings referenced, full copy reserved for clone and intentional, not a requirement; bulletproof correctness, we can iterate on perf". Skeptical review done: two blockers (String as `Class::Copy`, lending stage) removed; evidence relabelled.

## Problem

- Measured (`bench/agent/results/trials-2026-10-31.jsonl`): Manuscript 8/20 first builds against Go 18, Rust 16, TypeScript 18. The diagnostic counts in #2147 (`only a whole variable can move` 14, `moved here but used again` 28, `it only borrows its value` 9) come from transcripts that are not committed; 30 further hits there (`not declared var`, `declared with let`, `does not change its receiver`, parse) are outside this proposal.
- Verified with `ms check` at `a0f61d32` (`crates/ms-check/src/ownership/walk.rs:2006`):

```manuscript
fn label(r: Row) String:
    return r.name                 # accepted: a partial move, so `label` consumes `r`

let l = label(rows[0])            # error: cannot move `rows[..]` out of `rows`: only a whole variable can move
```

  The fix the diagnostic prints, `rows[0].clone()`, deep-copies the row; the cause is a field return three lines away. `fn title() String: return self.name` on an `impl` is rejected outright, and `seen.add(r.name, 1)` consumes `r` the same way.
- Verified: `var y = xs[0]; y += 10` prints `11 11` (#2168, `documentation/core-language/basics/bindings.md:80`), and `if var q = m.get("a"): q.append(1)` leaves the map unchanged with no diagnostic (#2164; `OWNERSHIP.md:29` still says the payload is borrowed, which `proposals/if-var-places.md` moved to `m[k]?`).
- Non-goals: write-through of `var x = f(b)` (rejected in `proposals/remove-ref.md`), a result that views its argument (`wiki/language/ref-is-removed-results-and-fields-own-their-value.md`), two owners of one container (`Shared[T]` stays the only way), the `var` marker at declarations and calls.

## Design

**Rule: plain data copies; a container has one owner; `.clone()` is written only to make a second independent container.**

Plain data is a scalar, `String`, `Bytes`, or a record or alternative whose fields are all plain data (a new predicate `plain(t)` in `ms-check`, beside `Class`, which is unchanged). `String` and `Bytes` are immutable (`documentation/core-language/basics/text-and-bytes.md:8`), so under exclusivity a copy and a reference of one cannot be told apart.

- `plain` is consulted at exactly three decision points of `ownership/walk.rs`: `bind` for `var x = place`, `projection` and `move_out` where a borrowed value reaches a consuming position, and the returned-part path of `partial_move`. Shared borrows (`let`, loop variables, payloads, non-escaping captures), the overlap check (`held`), temporaries and drops keep reading `Class`, so a `let w = names[0]` or `for w in words` still lends two words and allocates nothing.
- `var y = place` of plain data copies: `var y = xs[0]; y += 10` leaves `xs[0]` alone, `var s = r.name; s += "!"` leaves `r.name` alone. The scalar write-through exception (`bindings.md:80`, `OWNERSHIP.md` "Mutable borrows") is deleted; `var c = cs[0]` for a record of plain data flips from borrow to copy, so stage 1 reports every binding in the corpus and stdlib whose meaning flips.
- `var y = place` of a container stays an exclusive borrow (`var row = rows[0]; row.append(1)` changes `rows[0]`); `let x = place` stays a shared borrow for every type; `if var x = m[k]?` stays the in-place form.
- Plain data reaching a consuming position from a borrow (field, element, `Map.add`, `return`, escaping capture) is copied without `.clone()`, and the enclosing function no longer consumes its parameter for it: `label` above borrows `r`, and `label(rows[0])` is accepted. The copy is the one today's code writes as `.clone()`; `copyelim` (`crates/ms-mir/src/opt/copyelim.rs`, intra-function) removes it when the source is dead, and Release inlining removes more. Debug keeps the copy (`remove-ref.md`: `field_via_clone` 42 vs 22 Debug allocs, equal in Release).
- A container part of a live root cannot be stored (`out.append(src[0])` with `src` used later): the error stays, because a copy here would silently differ from the aliasing the writer expects, and the message names `.clone()` or moving the whole root. A container field of an owned local or parameter at its last use moves out as today.
- `if var x = e` where `e` is an owned `Optional` or `Result` whose payload is a container and `x` is changed but never read, stored or returned afterwards (per-place liveness in `live.rs`, no second analysis) is an error: "the change to `x` is lost: `x` is a copy of the payload; borrow the entry with `if var x = m[k]?`, or store `x` back". The same check covers `var x = m.get(k).get(default)`.
- Every remaining ownership diagnostic names the line to change and one fix (`label(rows[0])` would say "`label` consumes `r` because it stores `r.cells`"), and `ms guide` gains a worked example of the rules in under 20 lines.

Proposed behavior (unchecked: rejected or write-through at `a0f61d32`, see Problem):

```manuscript
type Row:
    name: String
    cells: List[Int]

fn label(r: Row) String:
    return r.name                 # copies; `label` borrows `r`

fn bump(var rows: List[Row]) Unit:
    var n = rows[0].cells[0]      # Int copies
    n += 1                        # rows unchanged
    var cells = rows[0].cells     # exclusive borrow of a container
    cells.append(n)               # rows[0].cells changes
```

Soundness (hypothesis until the corpus and the leak sweep pass): no rule adds a way to alias. Each change replaces a rejection with a copy or a borrow with a copy; exclusivity, lexical borrows, one owner per container, the overlap check and deterministic drops are untouched because `Class` and the borrow facts are untouched. Element move-out and lending results are out of scope: both were sources of use-after-free before (`proposals/one-borrow-model.md` Status) and are not needed for the rule.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check` `ownership/classify.rs` | `plain(t)` predicate; `Class` unchanged | unit test over scalars, `String`, `Bytes`, nested records, `List` |
| `ms-check` `ownership/walk.rs` | `bind`: no `var` borrow of plain data; `projection`/`move_out`: copy instead of reject or partial move; lost-change error | accept/reject fixtures per rule; `string_added_to_map_from_borrow.ms` reject → accept; `string_clone_makes_cost_explicit.ms` keeps checking; `var_borrow_*` fixtures re-recorded; `tests/conformance` |
| `ms-lower` `alias.rs`, `func.rs:531` (`owned()`) | no alias for plain data; `Op::Copy` at the consuming sites the checker now accepts (the only class-sensitive copy site; adapters in `closure.rs`, `iface.rs`, `eq.rs`, `text.rs` unchanged) | `make count-check` headers re-recorded with reasons; static and dynamic `Op::Copy`/`Drop` of `Str` per benchmark as in `proposals/owned-values.md` §6 |
| `ms-mir` `opt/copyelim.rs` | no change expected; measure | `opt_copyelim.rs` |
| `stdlib/*.ms` | delete `.clone()` on returned and stored plain data | stdlib e2e, `make conform`, `make leak-check` |
| docs | `bindings.md:80`, `references.md`, `collections.md`, `OWNERSHIP.md` (Model, Mutable borrows line 29-30, Partial moves), `DESIGN.md` decision 1, `ms guide` | `make docs-check`, `make repo-check` |

## Alternatives

- Do nothing: the rules are sound today; the cost is an unmeasured share of a 60% first-build miss rate and three open issues that are "by design". Stage 2 measures the share.
- Full write-through (`var x = f(b)` aliases `b`): needs lending inference with a body-dependent semantic flip, an ABI change for lenders and interface agreement; rejected in `remove-ref.md` and its Alternatives.
- Copy containers implicitly too (Swift without copy-on-write): silently diverges from the aliasing writers expect and copies lists on every store; lost on both correctness and speed.
- Reference counting or a tracing GC: gives up deterministic drops and the no-refcount decision; excluded by the user.

## Stages

Each stage is one PR on auto-merge, green on Linux, macOS and Windows, with `bench/perf` run before and after against `bench/perf/baseline-2026-10-28.md` and `ms check` time on the stdlib.

1. Plain data copies: `plain`, the three decision points, flip report, fixtures, stdlib sweep, docs. Gate: ownership corpus, `count-check` with a stated `Str` copy budget per benchmark, `leak-check`, `bench/perf` within noise.
2. Lost-change error, diagnostic rewrite, `ms guide` example. Gate: Haiku agent bench rerun (`bench/agent`, 20 programs) with the first-build rate recorded in `bench/agent/results`.

## Open questions

- Reverse these recorded decisions? `DESIGN.md:7` "strings are duplicated only by an explicit `.clone()`" and the 2026-10-22 visible-copy clause; `OWNERSHIP.md:22` "copies are declared, not inferred"; `owned-values.md` decision 1 "implicit copies are errors"; `remove-ref.md` and the wiki page "a returned part writes `.clone()`". Recommendation: yes for plain data only; the copies are the ones written today, and the `Str` copy budget in stage 1 keeps the count honest.
- Keep records of plain data in the copy set, so `xs.append(p); p.x = 1` leaves `xs[-1]` alone? Recommendation: yes; a point is a value in every language with records, and a record with a container field still has one owner.
- Should `local binding _ is never read` become a warning (#2147 asks)? Recommendation: separate decision; it is not an ownership rule.
