# Borrowed type arguments: `&T` as a real type argument, so `Iterator[&T]` and `List[&T]` mean what they say

* Status: **Stages 1a and 1b implemented** (2026-11-25); skeptical review: go with changes (split stage 1, drop `List[&T]` storage from this proposal). Stage 2 (a borrowed list that stores without cloning) remains `borrowed-element-lists`
* Authors: [Claude](https://claude.ai/code)
* Implementation: not yet implemented
* Supersedes / Extracted from: decision 0 of [borrowed-fields-and-looks](borrowed-fields-and-looks.md) ("`&` is not a checker type"), for type arguments; unparks [borrowed-element-lists](borrowed-element-lists.md); needed by [lazy-iterator-chains](lazy-iterator-chains.md) stage 4
* Direction: Chinmay, 2026-11-25: "iterator is [T] can't T take &T ?" and, on the answer, "yes we should have it as real type argument"

## Summary

- Problem: `&` is dropped from a type argument, so `Iterator[&Int]` accepts an owning counter, `Filtered[I Iterator[&T], T]` cannot return `&T?`, and `List[&T]` is a spelling that clones.
- Change: `&T` written as a type argument becomes a distinct checked type `Ref[T]` (kind `MS_TY_REF`), so bounds, inference and instances see it.
- Decision requested: the staging under Alternatives, chiefly that stage 1 (interfaces and generic records) ships before `List[&T]` storage (stage 2).

## Motivation

Measured 2026-11-25 on this checkout (`ms run`): a function `total[I Iterator[&Int]](var it I)` accepts both `ListIter[Int]` (`next() &T?`) and `Counter` (`next() Int?`, owned) and prints 6 for each. The interface cannot tell a lending iterator from an owning one.

```manuscript
type Filtered[I Iterator[&T], T] { source I; keep fn(&T) Bool }
fn var Filtered[I Iterator[&T], T].next() &T? { ... }
// today: "a `&` result points into an argument; mark that argument `hold`"
```

- A filter over borrowed items must yield borrows. The only alternative, cloning each kept item, is a hidden copy that breaks "borrow by default, `.clone()` is the only copy" and costs the speed lazy chains are for (owner and coordinator, 2026-11-25).
- `List[&T]` has the same gap: `out.append(elem)` into it clones because the checker sees `List[T]` (wiki: sorted collections are look records, not `List[&T]`).
- Facts today: `MsTypeRef.is_ref` survives in the AST (`ast.h:61`), `implements.c:182` compares written `&` on results, `lower_func.c:432` reads `args.ptr[0]->is_ref` for lists of looks. `&` never reaches `MsTy`.

## Proposed solution

`Ref[T]` is a type constructor written `&T` in argument position only. A bound `Iterator[&T]` then requires `next` to return `&T?`; an owning iterator no longer satisfies it, and `Seq[I, &T]` carries borrowed items.

```manuscript
fn firsts(hold names List[String]) List[&String] { ... }   // stage 2
fn var Filtered[I Iterator[&T], T].next() &T? { ... }      // stage 1: I is a look, so the result keeps its source
```

Rules:
- `&T` equals only `&T`; it never equals `T`. A `&T` value reads as a `T` where a borrow of `T` is accepted (member access, call arguments that are not `move` or `var`, `==`, `for`).
- `&&T`, `&T?` inside a type argument are rejected; `&T?` stays "optional of borrow" as today.
- A type variable bounded by `Iterator[&T]` makes a record that holds it a look (`look_record_within`), so `next() &T?` keeps the record's sources.

## Detailed design

**Stage 1: contracts and generic records.**
- `check/types.c`: add `MS_TY_REF`, one argument; intern like a generic instance; `ms_ty_display` prints `&T`; substitution and unification recurse into it.
- Type resolution (where `MsTypeRef.args` become `MsTy`s): an arg with `is_ref` and a non-scalar target builds `Ref[T]`. A scalar target (`&Int`) stays `Int`, as borrowed-element-lists decided: a copy of a scalar is a borrow.
- `check/implements.c`: matching an operation against `Iterator[&T]` requires a `&` result; today it checks the written flag only for the interface's own declaration. With `T := &X`, `next() T?` is `&X?`.
- `own/result_borrows.c`, `check/properties.c`: a variable bounded by an interface with a `Ref` argument counts as a look in `look_record_within` and in `declared_mask` (`look_receiver`).
- Inference: `xs.iter().seq()` yields `Seq[ListIter[T], &T]`; a closure `x => ...` over it takes `&T`, read as `T` in the body.
- Lowering: `Ref[T]` lowers to the layout of `T`, with the borrowed bit on records and results already carried by `ret_borrowed`; no new MIR type in stage 1.

**Stage 2: `List[&T]` storage** follows [borrowed-element-lists](borrowed-element-lists.md): a `borrowed` bit on the list's MIR type, append without clone, drop frees the buffer only. That proposal's skeptical review stays the gate; this change supplies the type it lacked ("written types do not reach lowering").

**Edge cases.**
- `T := &String` for `List[T]`, `Optional[T]`, `Result[T, E]`: instances of generic stdlib code see `Ref`; generic bodies that clone or `move` a `T` reject a `Ref` instance (`T Clonable` is false for `Ref`; `clone()` of it is a hidden-copy error unless written `.clone()` on the target).
- A `Ref` instance of a user interface method that returns `T` (owned) is rejected unless the method result is `&`.
- Existing programs: every `&` written in an argument today is erased; stdlib sites (`List[&String]` in `intrinsics.ms`) are the only ones, audited below.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/check/types.c`, `types.h` | `MS_TY_REF`, intern, display, substitute | check fixtures: `Iterator[&Int]` rejects an owning counter |
| `src/compiler/check/implements.c`, `bounds.c` | bound with a `Ref` argument demands a `&` result | `lazy-filter-borrowed.ms` |
| `src/compiler/own/result_borrows.c`, `check/properties.c` | `Ref` bound makes a record a look | `look-chain-returned` |
| `src/compiler/lower` | `Ref[T]` takes `T`'s layout | e2e `lazy-list-iterators.ms` |
| `src/stdlib` | `Filtered`, `Seq.filter`, borrowed `collect` | stdlib tests |
| docs, wiki | references, loops guide, one wiki page | `docs-check` |

## Alternatives considered

- Do nothing: `Filtered` clones each kept item; rejected by the owner (hidden copy, speed).
- A marker bound for lending iterators (`Iterator[T] & Lends`): narrow and quick, but adds a second way to say the same thing and leaves `List[&T]` parked; the owner chose the real type.
- Stage 1 only versus both together: stage 1 is enough for lazy chains and is reviewable alone; stage 2 needs MIR list types and drop glue.

## Review outcome and stage 1a

An independent reviewer reproduced the facts and ranked the risks of a distinct `Ref[T]`: unification and inference (`T := &X` leaks wherever `T` is also used owned; decision 0 records the stdlib breaking when tried), the `&T` to `T` coercion (every type-id compare), and clone or move in generic stdlib bodies. It asked for a smaller first step and for the soundness case to be stated.

Stage 1a (implemented, no new type kind): a bound written with a `&` argument (`I Iterator[&T]`) sets a bit on the variable (`MsTyVariable.lends`).
- A type satisfies the bound only if each operation it implements returns a `&` result (`ms_check_lends`); an owning `Counter` is rejected with a message naming the rule.
- A record that holds such a variable is a look (`look_record_within`), so `fn var next() &T?` keeps the record's sources. `Filtered[I Iterator[&T], T]` and `Seq.filter` use it; `xs.iter().seq().filter(...)` yields borrows and clones nothing.
- Soundness: an item survives the iterator's next call because every satisfying `next` has a `&` result tied to its own look sources, not to itself: `result_borrows.c` already rejects a `&` result of a `var` method on a record that is not a look.
- Source syntax is final: `Iterator[&T]` is what users write if `Ref[T]` lands later.

Not done: a `&T` type argument elsewhere (`List[&T]`, `Optional[&T]`, `Seq[I, &T]`), and borrowed-element-lists, which stays its own proposal with its own review.

## Stage 1b: `&T` as a real type argument (implemented)

Written `&T` in a type argument is the builtin `Ref[T]` row (`MS_BUILTIN_Ref`, `ms_ty_ref`), shown as `&T`. `&&T` and a borrow of a scalar collapse to the inner type. `&T?` and `&T!E` keep the flag on the payload (the ownership pass reads it), so every existing `&T?` result is unchanged.
- A value is read through its borrow: an expression of type `&T` has the type `T` (`body_set_type`, the expression entry in `exprs.c`).
- `ms_ty_shape` ignores borrows, so assignability treats `List[&String]` and `List[String]` as one shape; `ms_ty_same_view` is the same test for unification and bound checks. A bare type variable binds to the value (`List[T]` met by `List[&String]` gives `T = String`), so a stdlib method that clones its items still returns owned ones.
- `ms_check_implements` and `ms_check_property` look through a borrow, so `List[&String]` is Equal, Hashable and Clonable like `List[String]`.
- Lowering strips borrows (`apply_subst`): a `Ref` has its value's layout. The borrowed bit still comes from the declaration, as before.
- Not changed, and the reason stage 2 exists: `out.append(x)` into a `List[&T]` still clones, because the call is typed on the value. A borrowed `collect()` needs the borrowed list type of borrowed-element-lists.

## Open questions

- Is a `&T` value an argument for a `T`-typed `fn` parameter that is neither `move` nor `var` without a cast? Recommend yes (read-only borrow), as for `hold`.
