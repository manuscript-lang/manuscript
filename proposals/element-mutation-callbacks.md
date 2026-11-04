# Element mutation through callbacks: `modify(fn(var T) Unit)`

## Summary

- Problem: a callback cannot change the element it receives. `fn(T)` parameters are read-only and `fn(var T)` is a different function type, so `xs.for_each(fn var p: p.n = p.n + 1)` is a type error. The only way to change elements in a loop is `xs[i].n = ...` by index. With list-loop natives now borrowing their receiver (#2528), mutating the receiver from the callback is rejected too, so there is no in-place element update through a higher-order method.
- Change: add `var fn modify(change: fn(var T) Unit) Unit` on `List[T]`, and on `Map[K, V]` as `var fn modify(change: fn(K, var V) Unit) Unit`. The callback receives each element (map: each value, key read-only) as a `var` parameter and changes it in place. No new syntax and no new type: `fn(var T) Unit` already exists.
- Decision requested: approve the name `modify` and the scope (list and map values; sets excluded because a changed element would change its hash).

## Status

Proposal, 2026-11-04. Direction (Chinmay, 2026-11-03): "it should be possible to change the element from it".

## Design

- Receiver: `modify` is a `var fn`, so the receiver is a mutable borrow for the whole call. A callback that touches the container (`xs.append`, `xs[0]`, a captured `xs`) overlaps that borrow and is rejected by the existing operand overlap check (`check_overlap`), with its remedy `clone first`. Structure cannot change during the traversal, so the length is fixed and no snapshot is needed.
- Element: each call passes a mutable borrow of the slot. The callback may assign fields or the whole parameter (`fn var p: p = P(0)`). Nothing is copied: lowering passes the element pointer the way `fn(var List[Int])` arguments pass their variable today.
- Order and effects: in index order (map: insertion order); a fault stops the traversal and leaves earlier elements changed, like a loop that faults partway.
- Types: the callback type is `fn(var T) Unit` (map: `fn(K, var V) Unit`). `T` need not be `Clonable`: nothing is copied or returned.
- `for_each` stays read-only (`fn(T)`); `map` and `filter` still build new collections.

```ms
type P:
    n: Int

var xs: List[P] = [P(1), P(2)]
xs.modify(fn var p: p.n = p.n + 1)
```

A callback that changes the container is rejected:

```text
xs.modify(fn var p: xs.append(p))
```

## Touched components

- `stdlib/collections/collections.ms`: two declarations with doc comments.
- `ms-check`: no new rule; overlap, `var` parameter and function-type checks already apply. Add one reject fixture (callback changes the receiver) and one accept fixture.
- `ms-lower`/runtime: a native loop like `list_source` + `each_element` that passes `rec`/slot references as `Mode::Mutate` arguments; the same machinery as calling a `fn(var T)` value.
- `documentation`: one paragraph under function values and closures.

## Alternatives considered

- Give `for_each` a `var` parameter: breaks every existing `fn(T)` callback and function value passed to it.
- Overload `for_each` on parameter mode: overloading by function type does not exist in the language.
- Do nothing: element updates stay `for i in 0..n: xs[i].f = ...`. Works and needs no change, but it gives up the higher-order form for updates and invites the receiver-mutation pattern #2528 rejects.

## Testing

Accept: list of records, list of scalars (`fn var n: n = n + 1`), map values, empty receiver, fault partway. Reject: callback appends, removes or reads the receiver; `modify` on a set. `make count-check` and the stdlib doc-example check cover the new declarations.
