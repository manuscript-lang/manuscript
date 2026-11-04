# Element mutation through callbacks: `for_each(fn(var T) Unit)`

## Summary

- Problem: a callback cannot change the element it receives. `fn(T)` parameters are read-only and `fn(var T)` is a different function type, so `xs.for_each(fn var p: p.n = p.n + 1)` is a type error. The only way to change elements in a loop is `xs[i].n = ...` by index. With list-loop natives now borrowing their receiver (#2528), mutating the receiver from the callback is rejected too, so there is no in-place element update through a higher-order method.
- Change: `for_each` takes `fn(var T) Unit` on `List[T]` and `fn(K, var V) Unit` on `Map[K, V]` (Chinmay, 2026-11-04: make `for_each` take a `var` instead of adding a method). To keep every existing callback working, a function that does not change its parameter is accepted where `fn(var T)` is expected: `fn(T) Unit` converts to `fn(var T) Unit`. The reverse stays an error.
- Decision requested: approve the one-way conversion `fn(T)` to `fn(var T)` (a language rule) and the scope (list and map values; sets excluded because a changed element would change its hash).

## Status

Proposal, 2026-11-04. Direction (Chinmay, 2026-11-03): "it should be possible to change the element from it".

## Design

- Conversion: `fn(T) R` is accepted for `fn(var T) R`. It is sound because a callee that never changes its parameter is valid for a caller that allows a change. Lowering wraps the value in an adapter (like the optional-parameter adapters in `closure.rs`) that loads the slot and calls the original; a `fn x:` literal checked against `fn(var T)` is lowered directly with a read-only parameter, with no adapter. `fn(var T)` to `fn(T)` stays rejected: the caller would not expect a change.
- Receiver: `for_each` on a list or map becomes a `var fn`, so the receiver is a mutable borrow for the whole call. A callback that touches the container (`xs.append`, `xs[0]`, a captured `xs`) overlaps it and is rejected by the existing overlap check. Structure cannot change during the traversal, so no snapshot is needed.
- Element: each call passes a mutable borrow of the slot; the callback may assign fields or the whole parameter (`fn var p: p = P(0)`). Nothing is copied.
- Cost to callers: `for_each` on a receiver that is a `let` or a borrowed parameter no longer type-checks, because it now changes its receiver. That is the one user-visible break. Mitigation: keep a read-only `each(operation: fn(T))` for borrowed receivers, or accept the break and rewrite the callers. This is the open question below.
- Order and effects: index order (map: insertion order); a fault stops the traversal with earlier elements changed.
- Types: `T` need not be `Clonable`; nothing is copied or returned.

```ms
type P:
    n: Int

var xs: List[P] = [P(1), P(2)]
xs.for_each(fn var p: p.n = p.n + 1)
```

A callback that changes the container is rejected:

```text
xs.for_each(fn var p: xs.append(p))
```

## Touched components

- `stdlib/collections/collections.ms`: `for_each` signatures and doc comments; a `var fn` receiver.
- `ms-check`: the function-type conversion rule in assignability; no new ownership rule (overlap, `var` parameter checks already apply). Fixtures: accept (mutating callback, existing callbacks, named functions), reject (callback changes the receiver, `fn(var T)` where `fn(T)` is expected, `for_each` on a `let`).
- `ms-lower`: adapter for converted function values; native loop passes slot references as `Mode::Mutate` arguments.
- `documentation`: one paragraph under function values and closures, one in the collections guide.

## Alternatives considered

- Add `modify` beside a read-only `for_each` (earlier draft of this proposal): no language rule and no break, but two near-identical methods.
- Do nothing: element updates stay `for i in 0..n: xs[i].f = ...`.

## Open question

Does `for_each` on a `let` list stay legal? If yes, `for_each` keeps a read-only overload by receiver mutability, which the language does not have today; if no, callers over borrowed receivers rewrite to a `for` loop.

## Testing

Accept: list of records, scalars, map values, empty receiver, fault partway, every existing `for_each` call site in the stdlib and fixtures. Reject: the cases above. `make count-check` and the stdlib doc-example check cover the new declarations.
