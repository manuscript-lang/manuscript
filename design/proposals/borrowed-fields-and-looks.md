# Borrowed fields and looks: records, iterators and interfaces that keep using a value

* Status: **Proposed** (2026-11-25, against `main` at `0d4a416e`); skeptical review applied
* Authors: [Claude](https://claude.ai/code)
* Implementation: not yet implemented
* Supersedes / Extracted from: stage 5 of [argument-modes-in-signatures](argument-modes-in-signatures.md); revisits [borrowing-iterators](borrowing-iterators.md), whose `ref` field was written for the removed Rust implementation
* Direction: Chinmay, 2026-11-25: "yes do a design" (stage 5 after the signature stages merged); "borrowed views" for `Map.keys` and `Map.values`; "why can't slice return a borrow?"

## Summary

- Problem: a signature can now say a result keeps using an argument, but no *type* can: a record cannot hold a `&T`, so iterators clone each item, cursors copy their source, and an interface cannot return a view.
- Change: allow `&T` as a record field and as a type argument. A type that contains `&` is a *look*. A look is tied to its sources, freezes them, and cannot outlive or escape them.
- Decision requested: the five choices under Open questions, chiefly that `hold` on a look freezes the look's sources and not the look itself.

## Motivation

`Iterator[T]` (`src/stdlib/core/core.ms:244`) documents `next` as lending: "the item is a borrow ... an iterator over a container borrows from the container instead". Its signature `var fn next() T?` says nothing of the kind, and `loops.md:152` says the item is owned. After the signature stages a signature is the whole contract, so the interface has no way to state what its comment promises, and a user type has no type to write for the state that does the lending.

```manuscript
// rejected today: a field owns its value (references.md)
type Cursor {
    items List[String]   // owns the list, so walking it needs the list moved in
    at Int
}
```

- A user iterator over a container that returns a part of it with `T?` compiles and, hypothesis (unverified), copies each item at the return: `fn var Walk.next() String? { return self.items.first() }` type-checks in a scratch project.
- No stdlib type implements `Iterator`; `List`, `Set` and `Map` already borrow in `for` (`borrowing-iteration.md`). `LineReader` and `Deque` iteration exist only in old designs and are not ported.
- `Map.keys` is `&List[T]` (a borrowed list, `collections.ms`); `split` is `List[&String]` (a list of looks, `intrinsics.ms:114`). Only the second needs `&` as a type argument today.
- Non-goals: lifetime names, `&` in `Rc`, `Pool` or task state, a pointer to a single field, a lending iterator whose item borrows the iterator (a reader that owns its line): that needs `hold self` and cannot advance while an item lives, so it stays owned.

## Proposed solution

A record may hold a `&T` field. Building one ties the record to the values it is given, and the record then behaves like `&T` itself:

```manuscript
// proposed; `&` fields do not parse yet
type Cursor[T] {
    items &List[T]
    at Int
}

fn Cursor[T].new(hold items List[T]) Cursor[T]     // result is a look of `items`
fn var Cursor[T].next() &T?                        // an item looks at the list, not the cursor
```

`for x in Cursor.new(names)` binds `x` as `&String` and copies nothing. The workaround today is `for x in names` (a list loop) or an index loop; neither works through `Iterator[T]`.

## Detailed design

**Look types.** A type is a look if it is `&T`, a record with a `&` field, or a generic instance with a look argument (`List[&String]`, `Optional[Cursor[Int]]`). `&&T` is `&T`; `&` of a scalar is an error. Writing `&` in a field needs no `hold`: the field type says it.

**Sources.** Every look value has a set of *sources*: the owned places it looks at.
- `&T` result of a call: the sources of each `hold` argument. An owned `hold` argument contributes itself; a look-typed `hold` argument contributes *its sources*, not itself.
- A record literal or constructor call: the union of the sources of every `&` field value (an owned value given to a `&` field contributes itself; the expression must be a place, not a temporary that ends first).
- A part of a look (`cursor.items.get(i)`) has the look's sources.

**`hold` on a look.** `hold` on a parameter of look type freezes that parameter's sources until the result's last use, not the parameter. This is what lets `fn var Cursor[T].next() &T?` advance the cursor while earlier items live: the item is tied to `names`, `var` covers the position field, and the cursor stays free. A `&` result of a method whose receiver is a look needs no `hold` on the receiver (the receiver's sources are what it keeps); a plain-typed receiver still needs `hold` as in the parent proposal.

**Borrow by default, `move` to own (Chinmay, 2026-11-25).** A parameter borrows unless it is `move`; `move` is the only slot that takes ownership, and a borrow cannot be passed to it. A plain value can stand where a borrow is expected, never the reverse. So `&String` and `List[&String]` pass to a plain `String` or `List[String]` parameter (`join(s.split(","))` keeps working: `join` only reads), `String` passes where `&String` is written, and a look never flows into a `move` parameter, an owned field or an owned result without `.clone()` of each item. The checker erases `&`, so the ownership pass enforces this from the written types.

**What a look cannot do.** Be stored in an owned place (a record field of non-`&` type, a `List[T]` element, a captured variable of an escaping closure), be returned unless it is tied to a `hold` argument, be passed to a `move` parameter, or be sent over a pipe. The existing diagnostic names the fix: `.clone()` the item, or `hold` the source. `Cursor` is not `Clonable`, `Hashable`, `Data` or sendable. A look has no drop glue; owners of its sources free them.

**Iterators.** `Iterator[T]` is unchanged. `Iterator[&String]` is a valid instance; its `next` result `&String?` is a look, so `for` binds a borrowed item. Containers gain `fn hold List[T].iter() Cursor[T]` (a stdlib type, not a keyword). `for x in list` keeps its direct lowering; `iter()` is for passing a walk to a helper or interface parameter. A look-typed `for` source is held alone by the loop, so the owner cannot change inside it.

**Interfaces and function types.** A look may be an implementation's state. A call through an interface whose operation returns `&T` borrows from the argument the operation names, as in the parent proposal; the interface-view wrapper (`owned-interface-views.md`) carries the pointer.

**Result type arguments.** A generic `T` instantiated with a look makes `T?` a look at the call, so `ret_borrowed` is decided after instantiation for generic *instances*, not for the generic function body, which is checked once with `T` opaque (`hold` on a bare type parameter only freezes, as in the parent proposal).

**Lowering and runtime.** A `&T` field is a pointer. Record construction stores the pointer and no longer copies the value; record glue (drop, move, clone) skips `&` fields. The hidden copy at construction that stage 5 removes is the one listed in `references.md` ("a field owns its value"). `&T?` over a boxed optional needs a pointer to the element (the MIR rule in `borrowed-parts.md`, rule 6).

**Per-value sources.** Sources belong to a value, not a variable: reassigning a look variable drops its old sources and the borrow pass tracks them per assignment. A look operand counts as an operand over its sources, so `f(names, names.iter())` with `var` on the first is rejected like any overlap. Freezing covers change, move and `close()` of a source. A look-holding record may not touch a closed source: the holder's own `close` runs first as in `references.md`.

**Generics.** A look cannot go to a `move` parameter, so `List[&String].append` is unusable; `split` builds its list in the runtime. A generic `T` bound `Clonable` is not satisfied by a look. Glue, `ret_borrowed` and the interface-view wrapper are built per instance; the generic body is checked once with `T` opaque and no borrowed-result assumption.

**Edge cases.**
- An empty source (`items` has no elements): `next` returns `null`; no special case.
- The owner changes while a look lives: rejected, "`names` is frozen by `cursor`".
- A look returned from a function whose argument is a temporary: rejected unless the temporary lives to the end of the statement and the result does not outlive it.
- Nested look (`Cursor[Cursor[Int]]`) has the union of its sources.
- A `var` look (`var items &List[T]`) is not allowed in this proposal: a look reads its source.

**Diagnostics and tooling.** `` `cursor` looks at `names`; clone the item or keep `names` alive `` ; `ms fmt` prints `&T` with no space; the LSP shows a look's sources on hover; the agent skill gains one page.

## Fit with the language

- **Memory model:** one owner, borrow by default, `.clone()` the only copy. A look is a borrow with a name for its type; it removes copies, adds none.
- **Agent ergonomics:** the error names the source and the fix (`.clone()` or `hold`).
- **Names and syntax:** reuses `&` and `hold`; adds a field form, no keyword.
- **Platforms:** no change.

## Measured benefit

Hypothesis: iterating `Iterator[String]` over a list clones every string today; a look-typed iterator removes it. Measure before the iterator stage with a `bench/perf` list-walk through the interface against the latest dated baseline.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/syntax` | `&` in field types | parse and fmt fixtures |
| `src/compiler/check` | look types, sources, record construction ties | reject fixtures per escape |
| `src/compiler/own` | freeze sources of a look, `hold` on a look | borrow fixtures |
| `src/compiler/lower`, `mir` | pointer fields, no copy at construction, skip glue | e2e, leak check |
| `src/stdlib/*.ms` | `Cursor`, `iter()`, a stdlib iterator | conformance |
| `documentation/core-language/types/references.md`, `control-flow/loops.md` | replace "a type cannot hold a view of another variable"; iterators section | `docs-check` |

## Compatibility

Additive: no existing program holds a `&` field. `references.md` line "a type cannot hold a view of another variable" changes. Existing iterators stay valid.

## Alternatives considered

- **Do nothing:** iterators keep cloning, and a look cannot cross a helper or interface (the failing case above).
- **Smallest: `&` record fields with no iterator or interface work.** Lets cursors exist but not generic code over them; it is stage 5a below, not the end.
- **`ref` field marker as in `borrowing-iterators.md`:** same idea in the removed Rust syntax; `&T` is already the type form here, so reuse it.
- **Item borrows the cursor (`hold self`):** the cursor could not advance while an item lives; rejected for the `hold`-on-look rule.
- **A `View[T]` library type:** hides the rule in a generic, and the checker would need the same ties.

## Stages

0. Decision (tried and reverted 2026-11-25): `&` does not become a checker type. A distinct `List[&String]` id broke the standard library at once (`split` results no longer matched `List[String]` parameters) and would need a case in every integer type comparison of the checker. `&` stays what it is today, the `is_ref` flag on a written type (`ast.h:61`), erased by the checker. The ownership pass reads the flag from declarations, as `own/result_borrows.c` does for results, and tracks sources per value; lowering reads it from the field declaration to store a pointer. A read-only parameter therefore accepts a look with no conversion rule. Cost: a look flowing through a generic parameter is tracked by the pass at the call (the sources of each argument), not by the type.
1. `&` in field types with its escape rules together (a field with no tie would dangle): parse, check, fmt, lowering without copy, glue skip, construction ties, `hold` on a look. Gate: reject fixtures for reassigning a look (`c = b.iter()` then changing the old source), a look beside a `var` argument over its source, a temporary source, closure capture, pipe send, `Promise` of a look, `close()` of a frozen source; leak check.
2. Iterators (done, 2026-11-25): a user look record with a `&` field and `fn var next() &T?` iterates in `for` with no clones. A `&` result of a method on a look record keeps what the look keeps, so the receiver needs no `hold`; a view of a view freezes the owner. No stdlib `Cursor` or `iter()` (Chinmay: do not add a cursor type). Limit: an item still freezes the cursor, so `next` cannot run while an earlier item lives outside a `for`.
3. Interface looks: borrowed results through the interface-view wrapper. Gate: e2e with an interface-typed helper.

## Open questions

- `hold` on a look freezes its sources, not the look (recommended), so `next` can advance. The alternative freezes both and forces `iter()` results to be rebuilt per item.
- Is a look-typed record `Clonable`? Recommended no: `.clone()` an item, not the walk.
- Do record literals tie to a `&` field automatically (recommended), or need `hold` on a constructor? Automatic matches how `&T` is a type form.
- `Iterator[&String]` as an ordinary instance (recommended) versus a second interface `Looking[T]`.
- Per-component looks in `Result[&T, Error]` need the result ABI to say which component borrows (parent proposal, open); recommended as part of stage 4.
