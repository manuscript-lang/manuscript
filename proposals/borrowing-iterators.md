# Borrowing iterators: a value that holds a borrow, as in Rust

## Summary

- Problem: `Iterator[T].next()` returns an owned `Optional[T]`, and no value can hold a borrow, so an iterator over a container must clone each item (`T: Clonable`) or be replaced by a positional workaround (`Indexed`, #1904). Rust solves this with `Iter<'a, T>`: a struct holding `&'a Container`, with `Item = &'a T`.
- Change: a field may be declared `ref`, which makes its struct a borrow-carrying value. `Iterator.next` becomes `var fn next() ref Optional[T]`. Containers get an `iter()` returning a carrier; `for x in c` walks `c.iter()`. No lifetime syntax: origins are inferred, as the checker already does for `ref` results.
- The item borrows what the iterator holds (the container), not the iterator, so the iterator can advance while items are live.
- Cost: syntax (`ref` on a field), ownership checker rules, record glue for a non-owning field in MIR and lowering, stdlib migration (`LineReader`, containers), docs. `Indexed` is removed.
- Decision requested: approve stored borrows (the stage-5 deferral in `one-borrow-model.md`) in this restricted form.

## Status

Implemented in #1908, #1910 and the Iterable change. Proposal, 2026-10-29, against `main` at `d636bd3e`. Direction (Chinmay): "Can we update the iterator to just return ref instead of own value?"; "How about we make the container own the iterator?"; "Try to follow the Rust model as much as possible. Figure out the right way of doing it and just do it." Supersedes `borrowing-iteration.md` (#1904). `one-borrow-model.md` deferred `ref` in field and function types after review; this proposal revisits only fields.

## Problem

- `next() Optional[T]` must own: containers clone, non-`Clonable` items are excluded, and `LineReader` clones each line out of its stream.
- A cursor that takes the container as an argument (`next(source)`) type-checks today but a helper that takes the cursor cannot lend from the source (rejected: "`next` returns a part of `c`, `d`, which this function does not lend"), and it cannot be an interface-typed parameter. Review of that design: REVISE.
- Making the container its own iterator needs a position field, so loops cannot nest, a `let` container cannot be walked, and `next` must keep returning `none` after the end (a second loop sees nothing).
- Non-goals: lifetime syntax, `ref` in function types, `var ref` fields (a carrier reads its source, never changes it), lazy adapters (`map`, `filter`), carriers inside `List`/`Map`/`Set`.

## Design

```
type DequeIter[T]:
    source: ref Deque[T]
    position: Int

impl Deque[T]:
    fn iter() DequeIter[T]:
        return DequeIter(source: self, position: 0)

impl Iterator[T] for DequeIter[T]:
    var fn next() ref Optional[T]:
        let item = self.source.at(self.position)
        self.position += 1
        return item
```

Rules:

1. **Field.** `name: ref Type`. A type with a `ref` field, or with a field, payload or type argument that is a carrier, is a *carrier*. Carriers are `Move` class, not `Clonable`, `Equal`, `Hashable` or `Data`.
2. **Construct.** A `ref` field takes a place that outlives the value: a read-only parameter or receiver, or a place of a local. A temporary or an owned value being moved is rejected, as for a `ref` result. The new value holds a shared borrow of that place's origin.
3. **Hold.** A binding of a carrier holds the origins it was built from until its last use, exactly like `let y = f(b)` for a lending call; while held the origin cannot be changed, moved or reassigned.
4. **Return.** A carrier is returned only by constructing it in the `return` from read-only parameters or the receiver (`return Cursor(source: d, position: 0)`); its summary records those slots and the caller's binding holds the arguments' origins. A carrier built from a local, or any other carrier return, is rejected.
5. **Lend through a carrier.** In a method of a carrier, a returned part reached through a `ref` field belongs to the *held* origin of the receiver, not to the receiver. At the call, the result borrows what the receiver binding holds. `it.next()` therefore freezes the container, not `it`, and `it` can advance while earlier items are live.
6. **Linear and non-escaping** (narrowed after skeptical review: an unrestricted carrier is unsound). A carrier cannot be moved, reassigned, cloned, captured by an escaping closure, converted to an interface, stored in a collection, or have a `ref` field assigned after construction; it is built from places, never temporaries. It can be bound, passed read-only or `var`, and read in place.
7. **Interface calls** of a `ref` operation lend from the receiver binding and what it holds (conservative); a generic bound `I: Iterator[T]` therefore freezes the iterator. A concrete carrier call is precise.
8. **Runtime.** A `ref` field has MIR type `ref<T>`: a non-owning view with the leaves of `T` (`ref.new`, `ref.get`), never dropped or copied. The shallow copy is sound because the source is frozen while the carrier lives (rules 3 and 6).

Protocol:

```
export interface Iterator[T]:
    var fn next() ref Optional[T]

export interface Iterable[I]:
    fn iter() I
```

- `for item in source:` over a type with `Iterator` is expanded as today (`next` in a `while`); over a type with `Iterable` it holds `source.iter()` in a hidden `var` and iterates that. `Iterator` wins when both exist.
- `LineReader.next` keeps a one-slot field and lends it (the receiver is the origin, so the iterator is frozen while a line is live); a user `impl Iterator` must lend from its receiver or held origins (one-line migration: `ref`, store the item in a field).
- `Deque`, `Queue`, `PriorityQueue` implement `Iterable`; `Indexed` and `@std/indexed.ms` are deleted.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-syntax` | `ref` in a field declaration (`Field.by_ref`), parser, formatter | parser, format round trip |
| `ms-check` types and contracts | carrier property; excluded from `Clonable`, `Equal`, `Hashable`, `Data`; no `ref` fields in `List`/`Map` args | reject cases per rule 6 |
| `ms-check/ownership` | origins of a carrier construction, binding hold, `Slot::Held`, result-origin for carrier returns, escape rules | `tests/ownership/accept` and `reject` per rule |
| `ms-check` stmts | `Iterable` expansion in `check_for`; `ref` `next` | e2e |
| `ms-mir`, `ms-lower` | non-owning record field: construct, drop glue, verifier | MIR verifier tests, e2e under valgrind-style leak check (`make leak-check`) |
| `stdlib/core.ms`, `deque.ms`, `queue.ms`, `io.ms` | `Iterator` ref, `Iterable`, container iterators, `LineReader` | existing e2e, conformance fixtures |
| LSP, lint, docs | field `ref` hover and tokens, loops and references guides, `OWNERSHIP.md`, `one-borrow-model.md` update | snapshots, docs-check |

## Alternatives

- Keep `Indexed` (#1904): works, positional only; rejected by direction.
- Cursor with `next(source)`: no language change, but helpers cannot lend through it and it cannot be an interface-typed parameter; no gain over `Indexed` today.
- Container as its own iterator: shared position state, no `let` containers, rewind rule needed.
- Internal iteration (`each(visit)`): needs `break`/`return`/`try` protocol and `ref` in function types (deferred).

## Staging and verification

Each stage lands green on all three platforms.

1. Syntax, types, ownership rules and MIR support for `ref` fields, with a test-only carrier type and accept/reject corpora (every rule has a program that is accepted and one that is rejected).
2. `Iterator.next` becomes `ref`; migrate `LineReader`, tests, docs.
3. `Iterable`, container iterators, `for` expansion; delete `Indexed`.

Go/no-go after stage 1: an adversarial soundness review with valgrind-checked e2e programs (use-after-free attempts through return, move, reassignment, closures, interface calls).

## Open questions

- Names: `Iterable`/`iter`. Alternatives: `Walkable`/`walk`. Recommend `Iterable`/`iter` (Rust's `iter()`).
