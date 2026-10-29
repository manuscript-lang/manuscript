# Borrowing iteration: `for` over containers lends items instead of cloning them

## Summary

- Problem: `Iterator[T].next()` returns an owned `Optional[T]`, so a container that iterates through it must clone each item and needs `T: Clonable`. `Deque`, `Queue` and `PriorityQueue` have no `for` support at all; the only way to read them is `to_list()` (clones) or indexed `at`.
- Change: one new standard interface `Indexed[T]` (`length()` and `at(index) ref Optional[T]`). `for x in c:` over an `Indexed` binds `x` as a shared borrow of the item. No new syntax, keyword or runtime entry point.
- `Iterator[T]` stays for sources that produce values (`LineReader`, generators); borrowing is for containers that already hold the items.
- Cost: one interface in `stdlib/indexed.ms`, one checker expansion (a sibling of `check_iterator_for`), `impl Indexed` on three containers, docs and tests. No MIR, lowering, runtime or ABI change.
- Decision requested: approve `Indexed` as the borrowing protocol and the name.

## Status

Implemented, 2026-10-29. Direction (Chinmay): "can we do ref for peek and iteration"; "we're not popping item in iteration, so it would be a ref or borrow". Builds on `one-borrow-model.md` (a `ref` result is a borrow of the receiver, interface operations included, stage 4b) and `borrowed-results.md`.

## Problem

- `for x in deque` is rejected today: "for requires List, Set, Map, or an Iterator". An `Iterator` for a container would be `var fn next() Optional[T]`, which must own its result, so `T: Clonable`, and it needs a cursor field. A function value is going to stop being `Clonable`, so a container of callbacks could not be walked.
- A cursor type cannot lend: Manuscript has no stored references (`ref` appears only on results), so an iterator object cannot hold a borrow of its container.
- `next` returning `ref Optional[T]` does not fit either: `LineReader.next` owns a freshly read line, and a `ref` operation may only be implemented by a lending function (`one-borrow-model.md`).
- Non-goals: no stored borrows, no lazy adapters, no change to `List`/`Set`/`Map` iteration (already borrowed), no dropping `T: Clonable` from the containers (separate change; `pop_*` and `to_list` still clone).

## Design

The container names its items by position; the loop does the walking, so nothing stored has to hold a borrow.

```
# A container whose items can be read in place by position.
export interface Indexed[T]:
    # Returns the number of items.
    fn length() Int
    # Returns a borrow of the item at `index` counted from the first, or none when out of range.
    fn at(index: Int) ref Optional[T]
```

`Deque.at` already has exactly this signature. Source:

```
for item in deque:
    use(item)
```

is checked, lowered and analysed as (the same expansion mechanism as `Iterator`):

```
for $i in 0..deque.length():
    if let item = deque.at($i):
        use(item)
```

- `item` is a shared borrow of `deque` ending at its last use, so the existing rules apply: the body cannot mutate `deque` while `item` is live, and `item` cannot be moved out or returned without `.clone()`. Verified: `reject/indexed-for-mutates-container.ms`.
- `length()` is read once. A body that mutates the container after the last use of `item` is allowed (unlike `List`, whose iterable stays frozen for the loop); a shortened container makes `at` return `none` and the step is skipped, never a fault.
- A place is read where it stands, as fresh path nodes per use (ids must not repeat); a bare `let $c = place` would move the container. A non-place expression (`for x in make_deque():`) is held in a hidden `let`.
- Order is the container's: `Deque` front to back, `Queue` oldest first, `PriorityQueue` heap-array order (not dequeue order; documented).
- A type that implements both `Iterator` and `Indexed` iterates with `Iterator`.
- Rejected (diagnostic text extended): `for requires List, Set, Map, an Iterator, or an Indexed container, found {t}`.

Implementations (all in Manuscript):

- `Deque`: add `impl Indexed[T] for Deque` using its existing `length` and `at`.
- `Queue`: add `at(index)` over `items.get(head + index)`; `length` exists.
- `PriorityQueue`: add `at(index)` over `heap`; `length` exists.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/indexed.ms` | `Indexed[T]` interface (a new module: `core.ms` and `collections.ms` export lists are quoted by frozen diagnostics fixtures) | doc generation |
| `stdlib/deque.ms`, `queue.ms` | `impl Indexed`, `Queue.at`, `PriorityQueue.at` | e2e: iterate, break, continue, empty |
| `crates/ms-check/src/stmts.rs` | `indexed_item`, expansion in `check_for`, diagnostic | accept/reject cases, borrow rejection |
| `crates/ms-check/src/ownership` | unchanged: runs on the expansion | reject: mutate while borrowed |
| `ms-lower`, MIR, codegen, `ms-rt` | unchanged | |
| `ms-syntax` parser, formatter | unchanged (no syntax) | |
| `crates/ms-lsp/src/index.rs` | loop-binding lookup accepts an expansion ending in a range `for` | navigation snapshot |
| `documentation/` | iteration guide section | docs checks |

## Alternatives

- Do nothing: containers stay unreadable by `for`; non-Clonable `T` needs index loops. Rejected by the stated direction.
- `Iterator` with `next() ref Optional[T]`: breaks `LineReader` and every owning source; cursor cannot hold a borrow. Rejected.
- A second cursor protocol (`var fn next_ref() ref Optional[T]` on a view type): needs a stored borrow of the container. Rejected until the language has one.
- Make `for` call `at` on any type with `length` and `at`, no interface: implicit structural rule the rest of the language avoids (`for` uses `Iterator` by contract). Rejected.
- Support linked or tree containers: they need a different protocol; none exists in the stdlib today. Deferred.

## Staging and verification

- One stage: interface, checker expansion, three impls, tests, docs. Checks: `cargo nextest run --workspace`, `make conform`, clippy, fmt, `make repo-check`, `make docs`.
- Go/no-go: `tests/e2e/testdata/stdlib/borrowing-iteration.ms` (including a `Deque` of function values, `break`, `continue`, nested loops) passes on all three platforms' CI.

## Open questions

- Name: `Indexed` vs `Sequence`. Recommend `Indexed` (says what the contract needs).

## Review

Skeptic review (independent subagent), REVISE, all points applied or answered:

- Cloned expression ids: fixed with fresh path nodes (above).
- Frozen iterable differs from `List`: kept, stated above; mutation after the last use is safe because `at` is bounds-checked.
- LSP hover: fixed in `index.rs`; `ms-tooling/src/inspect.rs` only scans the stmt's own `loop_binding` and the expansion is walked by the checker.
- Static calls in the expansion are direct calls on the concrete type; the generic-bound case `fn f[C: Indexed[T]]` is not exercised and not claimed.
- `PriorityQueue` heap order is documented as not dequeue order; kept for symmetry.
- Evidence: containers had no `for` support (`for` rejected with "requires List, Set, Map, or an Iterator"), so the cost of doing nothing is `to_list()` clones or index loops at every call site; no call-site count was taken.
- The `Clonable` bound on the three containers is unchanged here; follow-up.
