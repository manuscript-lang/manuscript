# Remove `ref` from the language

Status: draft proposal, 2026-10-31, checked against main. Not reviewed by a skeptical reviewer yet; finalize after the list-element and string-view lending work lands (the gate below depends on it). Direction (Chinmay, 2026-10-30): "a sound and performant copy semantics implementation, no special casing, everything should be cleanly handled by language rules and semantics".

## Summary

- Problem: `ref` is a second ownership surface (result types, record fields, interface operations) whose only job is to avoid a copy the language would otherwise make.
- Change: every function returns an owned value. The compiler removes a copy when the result is only read and its source is unchanged for the result's lifetime. This is guaranteed by rule and unobservable, so it needs no keyword.
- Cost: write-through of `var xs = b.list()` goes away (it copies, like every other `var` binding of a call); borrowing iterators lose their `ref` source field.
- Gate: the four clone/ref count pairs must reach their `ref` floors with the `ref` variants deleted.
- Decision requested: approve removing `ref` once the gate holds.

## Problem

- `ref` is checked machinery: `ownership/` in `ms-check`, `ResultType = [ "ref" ], Type`, a `ref` record-field carrier, interface `ref` agreement, and the rule "a `ref` result freezes every borrowable argument".
- It changes no meaning. A program with every `ref` replaced by `.clone()` prints the same output; only allocation counts differ. The fixtures prove it (measured: `tests/ownership-counts`, `make count-check`):

| Pair | Debug allocs, ref / clone | Release allocs, ref / clone |
| --- | --- | --- |
| `get_via_*` | 26 / 26 | 23 / 23 |
| `field_via_*` | 22 / 42 | 22 / 22 |
| `view_via_*` | 22 / 42 | 22 / 42 |
| `lend_via_*` | 42 / 60 | 42 / 60 |

- `get` already matches: the copy of a list element read by `get` is elided today. `field` matches in release. `view` (a `trim` returned through `fn body(l: Line) ref String`) and `lend` (a `ref Node?` first child) do not.
- Non-goals: changing `var`, `.clone()`, moves, `Shared[T]`, or the lexical borrow rules for bindings of places (`let x = a.b`), which stay.

## Design

- Rule: a call result, field read or element read that is only read, and whose source is not changed, moved or dropped before the result's last use, is a view of its source. Otherwise it is an owned copy, as today. This is the existing "clone of an unchanged place is a view" elision made guaranteed and interprocedural.
- Interprocedural: the checker computes, per function, a summary "result is part of parameter k". It is an optimization input, never an error and never a signature, so it cannot flip semantics when a body changes (the objection in `infer-borrows-feasibility.md` came from write-through, which this removes).
- Natives: `bindings.json` declares the same summary for bodiless functions (`trim`, `Optional.get`, `Map.get`, `Shared.get`, interface-free). Interface operations summarize as the intersection of their implementations, or "owned" when unknown.
- Before and after, from `view_via_ref.ms`:

```
type Line:
    text: String

fn body(l: Line) String:
    return l.text.trim()

fn size(l: Line) Int:
    return body(l).length()
```

- `return l.text.trim()` is accepted (today it is rejected without `ref`, remedy `.clone()`); `size` reads the result in place, so the call allocates nothing. If a caller keeps the result past a change to `l`, it is a copy.
- Semantics:
  - Write-through is removed. `var ys = b.list()` binds a copy; mutate `b.items` directly.
  - Borrowing iterators (`Iterator[T].next` returning `ref T?`, `Deque`/`Queue` carriers with `source: ref ...`) return owned items and elide through the same rule. The carrier record keeps its source via an ordinary index or cursor, not a `ref` field.
  - Escape rule unchanged: storing a view in a collection, record, closure or return slot is a copy.
- Errors: none new. The `ref`-specific diagnostics (whole-parameter return, `let ref`, `for ref`, `match ref`) are deleted.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax` | drop `ref` token, `ResultType` prefix, field marker; keep a migration hint for one release | `ref_position_hints.rs` becomes the hint test |
| `ms-check` `ownership/` | replace declared lending with the inferred summary; delete `ref` agreement and freeze-all rule | conformance accept corpus unchanged |
| `ms-lower`, `ms-mir` | view-vs-copy driven by summary; no `ref` types in MIR | MIR verify, `count-check` |
| `stdlib/*.ms`, `bindings.json` | drop `ref` from 34 occurrences in 9 files; native summaries move to `bindings.json` | stdlib e2e, leak sweep |
| formatter, lint, LSP, VS Code | drop keyword and hints | tooling tests |
| docs | rewrite `types/references.md`, `grammar.md`, `contracts.md`, `loops.md`; `ms guide` | `make docs`, `make repo-check` |
| `ms-rt`, codegen | unchanged | |

## Alternatives

- Do nothing: keeps two surfaces and a freeze-all imprecision; costs readers a keyword per lender. Lost on the "one rule" direction, not on speed.
- Infer `ref` from bodies (prototype `infer-ref-prototype.patch`): feasible, but body edits flip write-through semantics silently and bodiless declarations still need the keyword. Lost.
- Keep `ref` on exported and interface functions only: two rules. Lost.

## Staging and verification

1. Land the lending work the gate depends on (list elements, string views). Per PR: `make verify`, `make count-check`.
2. Make the elision guaranteed for the four fixture pairs: each `*_via_clone.ms` header must equal its `*_via_ref.ms` floor in debug and release. This is the go/no-go gate.
3. Delete `*_via_ref.ms` and migrate stdlib and tests off `ref` with the summary in place; bench tables in `bench/perf` show no regression above noise.
4. Remove syntax, checker rules, docs, tooling; keep the migration hint.

All stages run on Linux, macOS and Windows; no test is disabled on any platform.

## Open questions

- Do borrowing iterators keep zero allocation per item? Recommendation: yes, gate on `borrowing-iteration` fixtures before stage 3.
- Is losing `var ys = b.list()` write-through acceptable? Recommendation: yes; it is the one visible behavior change and matches value semantics.
