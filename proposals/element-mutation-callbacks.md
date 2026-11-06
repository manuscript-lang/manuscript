# Element mutation through callbacks: `for_each(fn(var T))`

## Summary

- Problem: a callback cannot change the element it receives. `xs.for_each(fn var p: p.n = p.n + 1)` is a type error, and the only in-place update is `xs[i].n = ...` by index.
- Change: declare `List.for_each(operation: fn(var T) Unit)` and `Map.for_each(operation: fn(K, var V) Unit)`. A general checker rule makes the receiver changeable exactly when the callback argument changes its parameter. No new method, syntax, or type; readers keep working through #2725 (`fn(T)` stands in for `fn(var T)`).
- Decision requested: approve the rule below and the two declarations.

## Status

Implemented, 2026-11-06. Directions (Chinmay, 2026-11-06): no `modify`; "option 1, but rely on the general rule, no special casing the compiler"; a reader may stand in for a changer, never the reverse (merged, #2725). Replaces the earlier `modify` design.

## Problem

```ms
type P:
    n: Int

var xs: List[P] = [P(1), P(2)]
xs.for_each(fn var p: p.n = p.n + 1)
```

- Rejected today: `expected fn(P) Unit, found fn(var P) Unit`.
- `for_each` must stay callable on `let` and borrowed lists with read-only callbacks (19 call sites in 10 `.ms` files today).
- #2528 made list natives borrow their receiver, so a callback that touches the receiver is rejected; there is no in-place update through a higher-order method.

## Design

- Declarations: `fn for_each(operation: fn(var T) Unit) Unit` on `List[T]`, `fn(K, var V)` on `Map[K, V]`. The receiver stays declared `fn` (read). Sets are unchanged (a changed element would change its hash).
- General rule, in `call_modes` (`ms-check/src/ownership/modes.rs`), for any method call: the receiver mode becomes `Mutate` when the declared type of a callback parameter has a `var` position whose type is one of the receiver's type arguments, and the argument expression is a function that takes that parameter as `var` itself (its `Info.function_source` is unset). A reader argument was converted (#2725), so the receiver stays `Borrow`. No method name is consulted.
- Mutate receiver means the existing machinery applies unchanged: the receiver must be a `var` binding or a field of one, it is borrowed exclusively for the call, and a callback that touches it is rejected by `check_overlap` with its `clone first` remedy. Length is fixed during the call, so no snapshot is needed.
- Source methods: their summary (derived from the body) stays authoritative; the rule only adds `Mutate`.
- Order and faults: index order (map: insertion order); a fault stops the traversal and leaves earlier elements changed, like a loop that faults partway.
- Lowering reads the checker's per-call result, not the declaration. Today lowering treats a call as mutating from the declaration (`collection_mutation`, `effects.rs:13`; consumed at `call.rs:701`, `mutation.rs:292` and `:382`, `closure.rs:894` and `:1573`, `native.rs:1391`), so a `fn` receiver would take the plain-read path and could stay in registers. The walker therefore records `Fact::MutatesReceiver` on the call node when the rule fires, and one helper (`mutates_receiver(call)`) replaces the declaration test at those sites.
- Natives with a `var` callback position pass the element address (`ListAddr`; map: the entry value pointer); the callee takes the value from the slot and puts the final value back, as for any `var` argument (`var_argument`, `restore_var_arguments`). A fault in the callback leaves what a faulting direct `var` call leaves (unwind closes the slot's owner). A reader argument is lowered without the #2725 adapter and called with values; the call site picks the variant from `function_source`, which the loop builder receives as a flag, so read-only `for_each` pays nothing (to be measured, stage 3).
- Method values and dispatch: `let f = xs.for_each` has no argument, so the rule cannot fire; a method value of a method with a `fn(var T)` callback over the receiver's elements is rejected ("call it directly, or pass a reader"). Contract dispatch uses declared modes only, so the rule does not apply through an interface (stated, not hidden). `T` is matched by `same`, so a function-typed `T` behaves like any other.
- Source methods (SortedMap's `for_each` in `sorted.ms`) keep their body summary; they may declare `fn(var K, ...)` the same way once the rule is in.

```ms
xs.for_each(fn var p: p.n = p.n + 1)      // xs must be var: accepted
let ys = [P(1)]
ys.for_each(fn p: print("{p.n}"))         // reader: ys may be let
ys.for_each(fn var p: p.n = 0)            // rejected: `ys` is not a `var`
xs.for_each(fn var p: xs.append(p))       // rejected: overlaps the receiver borrow
```

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-check` `ownership/modes.rs`, `walk.rs` | receiver `Mutate` from a changing callback argument; `Fact::MutatesReceiver`; reject method values | accept and reject fixtures above, plus capture-the-receiver and method-value rejects |
| `stdlib/collections/collections.ms` | two declarations and doc comments | stdlib doc-example check |
| `ms-lower` `call.rs`, `mutation.rs`, `closure.rs`, `native.rs`, `iterate.rs` | read `Fact::MutatesReceiver`; pass the element address for a `var` position; reader path unchanged | accept: records, scalars, strings, map values, empty receiver, fault partway |
| `documentation` | one paragraph under function values | `make docs-check` |

## Alternatives

- Do nothing: element updates stay index loops; works, no change. Chosen against because Chinmay asked for the callback form; no count of intended users exists yet.
- `modify` method (earlier design): rejected by Chinmay; a second name for the same job.
- `for_each` always `var fn`: breaks every `for_each` on a `let` or borrowed receiver.
- Receiver mode by method name: special-cases the compiler; rejected.

## Stages

1. Checker rule and declarations behind the new reject fixtures; lowering for lists.
2. Map values; documentation.
3. Measure `for_each` before and after on `bench/perf` (reader path must not regress); record a dated section.

## Open questions

- Whether other callback methods (`map`, `filter`, `fold`) should later declare `fn(var T)` for in-place forms: the rule already covers them; not proposed here.
