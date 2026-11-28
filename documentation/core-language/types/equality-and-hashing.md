+++
title = "Equality and hashing"
weight = 8
+++

# Equality and hashing

- `Equal`: values can be compared with `==` and `!=`. Two values of the same type are equal when all their fields are equal, even if they are different objects.
- `Hashable`: a value yields a lookup code, used for map keys and set elements, which must also be `Equal`. The hash finds the entry, and equality resolves collisions.

Both are prelude interfaces from `@std/core.ms`; importing them is rejected.

`Comparable` (also in `@std/core.ms`) orders values for `math.max`, `math.min`, `List.sorted`, `List.min`, and `List.max`. It does not imply `Equal`: `Float` orders NaN above every value, yet NaN != NaN. When a type has both, make `compare` return zero exactly when `equals` is true.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
interface Equal {
    fn equals(other Self) Bool
}

interface Comparable {
    fn compare(other Self) Int
}

interface Hashable {
    fn hash() Int
}
```

`Self` is the implementing type. An implementation writes its own type for `other`, as `CustomerKey.equals` does below, so it never has to check the argument's type.

- In a bound `T Equal`, `Self` is `T`: `left.equals(right)` takes two `T`.
- Through an `Equal` or `Comparable` value, `Self` is that interface: values of different types are unequal, and ordering them faults.
- `Self` is allowed only as a whole parameter or result type of an interface operation.

`==` and `!=` use the visible `Equal` implementation. A custom `Hashable` requires an `Equal`. Matching method names alone never make a type implement either interface.

## Built-in value semantics

- `Bool`, `Int`, `Decimal`, `String`, `Bytes`, `Void`, `Duration`, and `Instant` are built-in `Equal` and `Hashable`; `Never` vacuously is.
- `Float` has IEEE equality (NaN is unequal, `0.0 == -0.0`) and no hashing.
- Strings compare exact Unicode scalars, without normalization. Decimal compares numeric value. Instants must share a clock domain.
- Types, enums, `Optional`, and `Result` compare by nominal type and all components. They satisfy each interface when all their components do.

| Collection | Equality | Hashing |
| --- | --- | --- |
| `List[T]` | Equal corresponding elements in order | Unsupported |
| `Map[K, V]` | Equal associations, independent of insertion order | Unsupported |
| `Set[T]` | Equal members, independent of insertion order | Unsupported |

Equality reads both collections, and the ownership rules prevent changing a collection while a comparison borrows it.

- Recursive comparisons have a depth limit; see [programming faults](../errors/faults.md#runaway-recursion). Ownership prevents constructing cyclic values.
- Collections and recursive types get no automatic hashing; an explicit pair may hash a stable identity.
- Functions, resource handles, and service handles have no implicit equality.
- To compare through an `Equal`-typed parameter or binding, call `.equals`.

## Domain identity

An explicit implementation can select identity instead of every field:

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
type CustomerKey {
    id Int
    label String
}

fn CustomerKey.equals(other CustomerKey) Bool {
    return self.id == other.id
}

fn CustomerKey.hash() Int => self.id
```

These implementations apply to operators, collection searches, and key lookup. Overriding equality disables automatic hashing, so write a matching `hash` before using the type as a key. Visibility follows the [contract rules](contracts.md#coherence-and-visibility).

## Key consistency

Equality must be reflexive, symmetric, and transitive, and equal values must hash equally. Hashes are lookup aids, not stable IDs or a serialization format.

A `Map` owns its keys and a `Set` owns its elements. Inserting a non-scalar value moves it at its last use; call `.clone()` first if you need an independent value afterwards.

Never change a stored key in a way that changes its equality or hash. Remove the key, change it, and reinsert it. A key changed in place stays filed under its old hash, so lookups find it under neither value.

Equality and hash must be deterministic and independent of authority, resource state, and wall-clock time.
