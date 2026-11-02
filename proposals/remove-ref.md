# Remove `ref` from the language

Status: implemented, 2026-10-31 (syntax, checker, lowering and fixtures removed in one change; stdlib lenders and the index-based `Iterable` landed first). Approved by Chinmay 2026-10-31: "let's rely on copy elision, make all methods return a copy". Skeptical review done (below). The dependency (list-element and string-view move-out) was investigated and dropped: no measured Release gain. Direction (Chinmay, 2026-10-30): "a sound and performant copy semantics implementation, no special casing, everything should be cleanly handled by language rules and semantics".

## Summary

- Problem: `ref` is a second ownership surface (result types, record fields, interface operations) whose only job is to avoid a copy the language would otherwise make.
- Change: delete `ref`. Every function returns an owned value; where a callee returned a part of a parameter it now writes `.clone()`, as the `*_via_clone.ms` fixtures already do. No new elision pass is built.
- Evidence: the count pairs differ in allocations only. Measured Release wall time shows no difference (below).
- Cost: write-through of `var xs = b.list()` goes away; borrowing iterators lose their `ref` source field.
- Decision requested: approve removing `ref`, gated on `bench/perf` showing no regression above noise.

## Problem

- `ref` is checked machinery: `ownership/` in `ms-check`, `ResultType = [ "ref" ], Type`, a `ref` record-field carrier, interface `ref` agreement, and the rule "a `ref` result freezes every borrowable argument".
- It changes no meaning. A program with every `ref` replaced by `.clone()` prints the same output; only allocation counts differ. The fixtures prove it (measured: `tests/ownership-counts`, `make count-check`):

| Pair | Debug allocs, ref / clone | Release allocs, ref / clone |
| --- | --- | --- |
| `get_via_*` | 26 / 26 | 23 / 23 |
| `field_via_*` | 22 / 42 | 22 / 22 |
| `view_via_*` | 22 / 42 | 22 / 42 |
| `lend_via_*` | 42 / 60 | 42 / 60 |

- `get` already matches; `field` matches in release; `view` and `lend` carry extra callee-side allocations.
- Measured wall time (Release, best of 2, `lend_via_clone.ms` shape written with `.clone()` vs a move through `pop()`, so no copy): deep descent 200k iterations clone 7.74-7.87 s vs move 7.97-8.17 s; shallow descent 3000 iterations on a depth-9 tree, where the clone copies about 40% of the tree, 1.25-1.42 s vs 1.33-1.38 s. The difference is inside noise. The string-view case was not timed; it has the same shape (one small allocation against hundreds of ns of other work).
- So `ref` buys allocation counts, not speed, in the measured cases.
- Non-goals: changing `var`, `.clone()`, moves, `Shared[T]`, or the lexical borrow rules for bindings of places (`let x = a.b`), which stay.

## Design

- Rule: a function result is always owned. Returning a part of a parameter needs `.clone()`, the remedy the checker already prints for a non-`ref` function.
- No interprocedural summary and no guaranteed elision are added. The existing intra-function elision (get, release `field`) stays as is. Reasoning: the elision machinery is the large change, and the measurements above show it buys no wall time.
- Before and after, from `view_via_ref.ms`:

```
type Line:
    text: String

fn body(l: Line) String:
    return l.text.trim().clone()

fn size(l: Line) Int:
    return body(l).length()
```

- This is `view_via_clone.ms` and checks today. Cost: 42 allocs instead of 22 in that fixture, no measured time.
- Semantics:
  - Write-through is removed. `var ys = b.list()` binds a copy; mutate `b.items` directly.
  - Borrowing iterators (`Iterator[T].next` returning `ref T?`, `Deque`/`Queue` carriers with `source: ref ...`) return owned items. Large items cost a clone per step; if `bench/perf` shows a regression, that iterator uses a cursor rather than reintroducing `ref`.
  - Bindings of places (`let x = a.b`) keep their lexical borrow rule.
- Errors: none new. The `ref` diagnostics (whole-parameter return, `let ref`, `for ref`, `match ref`) are deleted.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax` | drop `ref` token, `ResultType` prefix, field marker; keep a migration hint for one release | `ref_position_hints.rs` becomes the hint test |
| `ms-check` `ownership/` | delete lending results, `ref` agreement and the freeze-all rule | conformance accept corpus migrated |
| `ms-lower`, `ms-mir` | drop `ref` types in MIR | MIR verify, `count-check` headers re-recorded with stated reasons |
| `stdlib/*.ms`, `bindings.json` | drop `ref` from 34 occurrences in 9 files; natives that lent now return owned values | stdlib e2e, leak sweep |
| formatter, lint, LSP, VS Code | drop keyword and hints | tooling tests |
| docs | rewrite `types/references.md`, `grammar.md`, `contracts.md`, `loops.md`; `ms guide` | `make docs`, `make repo-check` |
| `ms-rt`, `ms-clif`, ABI | lending natives return owned values; `bindings.json` and interface method tables follow | leak sweep, native tests |

## Alternatives

- Do nothing: keeps two surfaces and a freeze-all imprecision; costs readers a keyword per lender. Lost on the "one rule" direction; speed is not the argument either way.
- Guaranteed interprocedural elision (the earlier draft of this proposal): would close the alloc gap, but needs owned-parameter variants and element/view move-out, a large change with no measured Release gain. Lost.
- Infer `ref` from bodies (`infer-ref-prototype.patch`): body edits flip write-through semantics silently and bodiless declarations still need the keyword. Lost.
- Keep `ref` on exported and interface functions only: two rules. Lost.

## Staging and verification

Each stage is its own PR on auto-merge and lands green on Linux, macOS and Windows; no test is disabled.

1. Evidence first: run `bench/perf` (5 runs, stated noise band) plus a hot `trim()` / `Map.get` loop over large values; record in `bench/perf` results. Update the `lend_via_clone.ms` header that names guaranteed elision as the precondition for removing `ref`, and say why it is dropped (no measured wall-time gain).
2. Leaf lenders, one family per PR, each re-recording `count-check` headers with the reason: `trim*`, `List.get/first/last`, then `Map.get`, then `json` and `http`.
3. Interface and carrier lenders together, because every implementation of a `ref` operation must agree: `Iterator.next`, `DequeIter`, `QueueIter`, `PriorityQueueIter`, `io.ms` line reader, and the `source: ref` carrier fields.
4. Remove syntax, checker rules, MIR `ret_borrowed`, docs (`references.md`, `grammar.md`, `OWNERSHIP.md`), tooling; keep a migration hint for one release.

## Skeptical review outcome

- Wall-time evidence was thin (best of 2, clone vs move, not vs `ref`, no string views). Addressed by stage 1 before any migration.
- Fixture headers named guaranteed elision as the precondition. Addressed in stage 1.
- Non-Clonable and generic lenders (`Optional.get`, `Shared.get`, `Deque.front/back/at`, `Iterator.next`): an owned return needs `T: Clonable` (`stdlib/core.ms:172`), which excludes functions, interface values and resource handles. Decision: add the bound; resources are taken with `pop`/`take`, not read with `get`. This is a visible API change; see Open questions.
- `ms-rt`/codegen are not unchanged: lending natives (`trim`, `Map.get`) return owned values, which changes `bindings.json` ABI and `ret_borrowed` in `ms-mir/src/types.rs`. Components table to include `ms-clif`, interface method tables, `OWNERSHIP.md`.
- Stage 1 of the earlier draft could not stay green incrementally (interface `ref` agreement); stages are reordered as above.

## Open questions

- Is losing `var ys = b.list()` write-through acceptable? Recommendation: yes; it is the one visible behavior change and matches value semantics.
- Is a `T: Clonable` bound on `Optional.get`, `Shared.get`, `Deque.front/back/at` and `Iterator.next` acceptable? Recommendation: yes (matches "all methods return a copy"); resource containers are consumed with `pop`/`take`.
- Do iterators over large element types regress? Recommendation: measure in stage 1 and fix with a cursor, not `ref`.
