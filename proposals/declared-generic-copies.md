# Declare copies of a type parameter with `Clonable`

## Summary

- Today, generic code copies values of a type parameter `T` without saying so. The checker infers each copy (`Summary.copies`), propagates it through every generic call, and rejects instances where `T` is a resource. The inference has had holes: two double closes, fixed in #2011.
- `Clonable` has its own name table: `Regex`, a list of native types, functions and interfaces are excluded by name.
- Change, in two parts:
  1. `Clonable` means "not a resource".
  2. A copy of `T` requires `T: Clonable`, written in the signature.
- Removed: the copy inference (`note_copied`, `Summary.copies`, `generic_copies`, `implementation_copies`), the `fill`/`copy_within`/`merge` name list, the `List`/`Map`/`Set` copy heuristic, and `clonable`'s name table.
- Cost, measured: 24 generic functions in the whole repository gain `T: Clonable`, about 10 of them in stdlib. Concrete code is unaffected.
- Cost, structural: `impl` blocks take bounds from declarations (`documentation/core-language/basics/grammar.md:172`), so a generic type's method that copies `T` needs `type Stack[T: Clonable]`, which rules out `Stack[Door]`, or a bounded interface (`ListToSet` pattern). Today's inference rejects only the copying call.

## Status

- Proposal, 2026-10-31, against `origin/main` 7c78a8b2 plus #2011.
- Direction (Chinmay): "sound and performant copy semantics ... no special casing, everything should be cleanly handled by language rules and semantics".
- `skills/language-design-taste/SKILL.md:11,18`: public contracts explicit; "the `Clonable` bound lets generic code keep a value it only borrows".
- A skeptical review of the first draft found the two holes and showed that the old `Clonable` would reject `List[Shape].filter`, `List[fn(Int) Int].reversed()` and `[share(1)].take(1)`. Part 1 answers that objection.

## Problem

- Copy decisions are inferred from names and type shapes (verified at 7c78a8b2):
  - `ownership/walk.rs:2936-2950`: the `fill`, `copy_within` and `merge` list.
  - `walk.rs:2953-2987`: the copy heuristic, limited to `List`/`Map`/`Set`.
  - `note_copied` at `walk.rs:2441,2760,2786`.
  - `generic_copies` at `walk.rs:2794`.
  - `Summary.copies` at `modes.rs:58`.
- Inference misses paths. On main, `via[T: Dup](Bag([Door(1)]))` and `outer[T] = apply(xs, keep[T])` each closed a `Door` twice. #2011 patches both by adding more inference (`implementation_copies`).
- The error names an instantiation, not the copy, for example ``spawn` copies values of its type parameter `Out``. The cause is inside another function.
- `clonable` (`contracts.rs:714-742`) excludes `Regex`, every native except `Bytes`/`Decimal`/`BigInt`, functions and interfaces, by name.

Non-goals:

- Classes (`Copy`/`Move`/`Resource`) are unchanged.
- D4 (#1999) and D6 (#2002) are unchanged.

## Design

1. `Clonable` holds for every type except a resource: a `Closeable` type, a `Closeable` interface value, a type parameter without the `Clonable` bound, or a type holding one of those.
   - Functions copy by sharing their environment. That is safe because an escaping closure cannot change its captures (verified: "this closure changes captured `n`, so it cannot be returned...").
   - A captured resource closes once, when the last copy is released (verified: one `close 1` after `fs.reversed()` and `fs.take(1)`).
   - Interface values other than `Closeable` never hold a resource (the H1 rule, #1988).
   - Natives copy by their declared clone, or share as handles (D4).
2. Any operation that copies a value of `T` requires `T: Clonable`. That covers a standard-library method that returns or stores copies of elements, and the implicit copy sites: a lambda parameter kept, an interface adapter, a function value.

```ms
fn twice[T: Clonable](xs: List[T]) List[T]:
    return xs.concat(xs)

fn first_two[T](xs: List[T]) List[T]:
    return xs.take(2)  # error: `take` copies elements of `List[T]`; declare `T: Clonable`
```

- Bound checking then does what the inference did:
  - `[Door(1)].take(1)` fails with an unsatisfied bound.
  - `impl Dup for Bag[U]` calling `take` must itself declare `U: Clonable`, so `Bag[Door]` does not implement `Dup`. That closes the #2011 holes by construction.
- Standard library: the copying `List`/`Map` methods move into `Clonable`-bounded interfaces, as `ListToSet` already does. The methods are `concat`, `take`, `drop`, `slice`, `reversed`, `sorted`, `filter`, `find`, `find_last`, `chunks`, `windows`, `partition`, `zip`, `entries`, `group_by`, `distinct`, `fill`, `copy_within`, and on `Map`: `merge`, `values`, `entries`, `keys`, `filter`, `map_keys`, `get_or`, `find`, `find_last`.
  - `Set` needs no bound, because a `Hashable` element is never a resource.
  - Lowering is unchanged, but the native dispatch for methods declared in an interface implementation has to be verified.

## Evidence (measured 2026-10-31)

- Experiment 1: part 1 alone (in `contracts.rs::clonable`). `make conform` passed 2401/2401 and `cargo test -p ms-check` passed. A generic `dup[T: Clonable]` over a closure, an interface value and `share(5)` ran correctly.
- Experiment 2: every `note_copied` of a type parameter without `Clonable` was logged by `ms check` over all 5037 accepted `.ms` files.
  - Exactly 24 distinct generic functions copy a type parameter.
  - In stdlib: `ListOrder.sorted`, `MapUpdate.update`, `MapCloseValues.close_values` (copies keys), `Deque.push_front`/`push_back`, `tasks.group_end`, `process.spawn`, `net`/`processes` `serve`, `toml.locate`, `test/property.pairs`.
  - The rest are tests and bench sources.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check/src/contracts.rs` | `clonable`: not a resource | accept `clonable_function_interface_shared` |
| `stdlib/collections.ms` | Copying methods move to `Clonable`-bounded interfaces | conformance corpus |
| `ms-check/src/ownership/walk.rs`, `modes.rs` | Remove the copy inference. The three implicit sites check `Clonable` locally | reject tests `generic_copy_*` and the #2011 tests, rewritten to the bound error |
| 24 generic functions (stdlib, tests, bench) | Add `T: Clonable` | `make conform`, `make e2e`, `make verify` |
| `ms-lower` | unchanged, apart from verifying native dispatch through interface implementations | e2e |
| `crates/ms-check/OWNERSHIP.md` | Replace the copy-inference text with the rule | |

## Order

- After #2011.
- Independent of D6.
- With D4 (#1999): natives that declare `clone` are `Clonable`, and the others share as handles. Part 1 is agnostic to which.

## Alternatives

- **Keep inference (do nothing).** No annotations are needed, but every new copy path needs another inference rule (#2011 added one). Errors point at instantiations.
- **Name lists generalized to every native.** Still name-based, and a new method has to be remembered.
- **Write `fill`, `copy_within` and `merge` in Manuscript.** Removes one name list only.
