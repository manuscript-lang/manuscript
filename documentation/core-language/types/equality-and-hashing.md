+++
title = "Equality and hashing"
weight = 8
+++

# Equality and hashing

- `Equal`: values can be compared with `==` and `!=`. Records of the same type are equal when all fields are equal, not only when they are the same object.
- `Hashable`: a lookup code for map keys and set elements, which also require `Equal`. The hash finds the entry; equality resolves collisions.

Both are prelude interfaces from `@std/equality.ms`; importing them is rejected. They are independent of sharing and resource lifetime.

`Comparable` (also in `@std/equality.ms`) orders values for `max`, `min`, and `List.max`/`min`. It does not imply `Equal`: Float orders NaN above every value yet NaN != NaN. Make `compare` return zero exactly when `equals` is true.

```manuscript
interface Equal:
    fn equals(other: Equal) -> Bool

interface Hashable:
    fn hash() -> Int
```

`==` and `!=` select the visible `Equal` implementation. A custom `Hashable` requires an `Equal`. Matching method names alone never establish either interface.

## Built-in value semantics

- `Bool`, `Int`, `Decimal`, `String`, `Bytes`, `Unit`, `Duration`, and `Instant` are built-in `Equal` and `Hashable`; `Never` vacuously is.
- Float has IEEE equality (NaN is unequal, `0.0 == -0.0`) and no hashing.
- Strings compare exact Unicode scalars, without normalization. Decimal compares numeric value. Instants must share a clock domain.
- Records, alternatives, Optional, and Result compare nominal type and all components, and satisfy each interface when all components do.

| Collection | Equality | Hashing |
| --- | --- | --- |
| `List[T]` | Equal corresponding elements in order | Unsupported |
| `Map[K, V]` | Equal associations, independent of insertion order | Unsupported |
| `Set[T]` | Equal members, independent of insertion order | Unsupported |

List equality captures both backing slices and lengths first, following the [captured-header traversal rules](collections.md#mutation-and-copies): element writes during comparison are visible, append, shrink, and reallocation are not.

- Structural equality terminates on cyclic data.
- Collections and recursive types get no automatic hashing; an explicit pair may hash a stable identity.
- Functions, resource handles, and service handles have no implicit equality.
- Compare through an `Equal` view with `.equals`.

## Domain identity

An explicit implementation can select identity instead of every field:

```manuscript
type CustomerKey:
    id: Int
    label: String

impl Equal for CustomerKey:
    fn equals(other: Equal) -> Bool:
        match other:
            CustomerKey(value): return self.id == value.id
            _: return false

impl Hashable for CustomerKey:
    fn hash() -> Int: self.id
```

These apply to operators, collection searches, and key lookup. Overriding equality disables automatic hashing, so provide a matching `hash` before using the type as a key. Visibility follows [contract rules](contracts.md#coherence-and-visibility).

## Key consistency

Equality must be reflexive, symmetric, and transitive, and equal values must hash equally. Hashes are lookup aids, not stable IDs or a serialization format.

Never change a stored key's equality or hash. Remove it, mutate, and reinsert; a mutated key stays filed under its old hash and neither value finds it. Equality and hash must be deterministic and independent of authority, resource state, and wall-clock time.
