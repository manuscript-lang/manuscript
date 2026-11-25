# Lists of borrowed elements: `List[&T]` that stores the element, not a copy

* Status: **Proposed** (2026-11-25, against `main` at `4b1d4936`). Skeptical review: no-go as written. Written `&` types do not reach lowering (facts hold erased types), a second list type needs drop, clone, descriptor and shape-table entries, and `set`, `remove`, `pop`, a consuming `for` and implicit clones need borrowed variants. Needs the encoding and propagation (inferred bindings, Optional, closures, generics) specified before build. Interim: sorted keys, values and range return look records (#6990)
* Authors: [Claude](https://claude.ai/code)
* Issue: #6990
* Direction: Chinmay, 2026-11-25: "it can copy the reference, but not value"; over-freezing sources is accepted ("we need to be correct"); `&` stays erased in the checker (card "Keep & erased, tag at lowering")
* Supersedes / Extracted from: stage 5 of [borrowed-fields-and-looks](borrowed-fields-and-looks.md), which decided `&` is not a checker type (decision 0)

## Summary

- Problem: `List[&T]` is only a spelling. `out.append(self.keys[c][at])` in `sorted.ms` clones each element; `SortedMap.keys()` copies 1000 keys as 1001 string clones although documented as views.
- Change: a list written `List[&T]` keeps shallow copies of its elements and never drops them. The checker is unchanged apart from tracking sources; lowering reads the written type.
- Decision requested: the open questions at the end.

## Motivation

- Measured (stats runtime, #6990): `for k in m.keys() { ... }` on a 1000-key `SortedMap[String, Int]` gives `string_clones=1001`; without the call, 1.
- User code cannot build one: `out.append(xs[i])` into a `List[&String]` is rejected ("hidden copy, write `.clone()`"), and `.clone()` makes the list own a copy nothing frees correctly. Only runtime natives (`split`, `lines`, `chars`) return borrowed lists, and only because a `String` view has no capacity and is never freed.
- Stdlib bodies skip the hidden-copy check, so `sorted.ms` compiles and copies silently.

## Proposed solution

```manuscript
fn firsts(hold names List[String]) List[&String] {
	var out List[&String] = []
	for name in names {
		out.append(name)   // stores a shallow copy; names stays the owner
	}
	return out             // ok: tied to `names`, which is `hold`
}
```

An element of `List[&T]` has the layout of a `T` and is a bitwise copy of the owner's value. The list frees its buffer and never the elements, so nothing is copied or double freed. `List[&T]` passes to a parameter that only reads a `List[T]` unchanged.

## Detailed design

**Checker (unchanged types).** `&T` stays an erased flag on the written type, as in decision 0. The ownership pass reads the flag from the written type at a list: a binding, a parameter, a function result, a field. A call `xs.append(arg)` whose receiver is a binding declared `List[&T]` is a store of a look: the list gains the arg's sources (`own/look_stores.c` already records stores and scopes), so the owner is frozen while the list is used and the list cannot outlive it or be returned without `hold`. An argument must be a place or a borrowed result; an owned temporary is rejected.

**Lowering.** `lower_types.c` already sets a per-field `borrowed` bit from the declaration. A list gets the same bit on its MIR type: `MirTyData` gains a `borrowed` flag, so `list<&T>` and `list<T>` are two interned types of one layout. Written types reach lowering through new facts on the binding, result and call, read the way `ret_borrowed` is.

**Operations on a borrowed list.**
- `append`, `insert`, `set`: store the element bitwise, with no `clone` and no move of the source.
- Reads (`get`, index, `for`, `length`, `first`): unchanged; the element is a borrow either way.
- `clone`: rejected, as for a record with a `&` field. `sort`, `reverse`, `slice` move elements inside the buffer and stay valid.
- Drop (`glue.c`): free the buffer only. Move and `take`: the list moves as a whole; taking an element out is rejected.

**Reading through `List[T]`.** A `List[&T]` argument to a parameter typed `List[T]` is allowed when the callee does not `move` or `var` it. MIR gets one no-op `list.view` cast at the call so the verifier sees matching types; layout and callee code are shared. A `move`/`var` parameter rejects it.

**Edge cases.** A scalar `T` (`List[&Int]`) is the same as `List[Int]` and `&` on it is accepted but ignored. A generic `T` instantiated with `&U` is handled at the instance, not in the generic body. A list built by a native (`split`) is already borrowed: its MIR type is marked and its drop unchanged.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/own` | list store of a look; reject temporaries and owned moves | conformance reject: temporary, local outliving owner |
| `src/compiler/check` | expose the written `&` of list args as a fact | check fixtures |
| `src/compiler/lower` | declaration types to `borrowed` list type; append/insert/set without clone | run fixture, leak and valgrind runs |
| `src/compiler/mir` | `borrowed` bit on the list type, `list.view` cast, glue drop frees buffer only | MIR verifier tests |
| `src/stdlib/collections/sorted.ms` | keys/values/range/values build real borrowed lists | `string_clones` 1001 to 1 |
| docs, wiki | `references.md`, wiki page | docs-check |

## Alternatives

- Do nothing: sorted collections keep copying in violation of "no hidden copies" and their own docs.
- Look records (`SortedRef`-style) for the four APIs: no compiler work, but the API changes and `split` and user code gain nothing.
- A distinct checker type: tried and reverted 2026-11-25; `split` results stopped matching `List[String]` parameters.

## Stages

1. Spike behind tests: written `List[&T]` reaches lowering as a fact; MIR flag; append stores bitwise. Check: `sorted.ms` `keys()` shows 1 clone.
2. Ownership rules and rejection tests; `list.view` cast for read-only `List[T]` parameters.
3. Move all four sorted APIs; docs and wiki; `split`, `lines`, `chars` use the same flag.

## Open questions

- Is `.clone()` of an element into a `List[&T]` rejected (recommended: yes, nothing frees it)?
- Do `sort`/`reverse` stay allowed on a borrowed list (recommended: yes)?
