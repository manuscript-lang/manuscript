+++
title = "Equality and hashing"
weight = 8
+++

# Equality and hashing

`Equal` means **values of this type can be compared with `==` and `!=`**. For example, two strings are equal when they contain the same text. By default, two records of the same type are equal when all their fields are equal; they do not need to be the same object.

`Hashable` supplies an internal lookup code for **map keys and set elements**, which also require `Equal`. A map uses the hash to find an entry quickly, then checks equality to distinguish keys that happen to have the same hash. A set uses the same process to recognize an existing element.

`Equal` and `Hashable` are operation interfaces defined in `@std/equality.ms`. Their names remain available in the prelude for generic bounds; explicit imports also work. Equality and hashing are independent of sharing and resource lifetime.

```manuscript
interface Equal:
    fn equals(other: Equal) -> Bool

interface Hashable:
    fn hash() -> Int
```

`==` and `!=` select the visible `Equal` implementation. Map keys and set elements must support both equality and hashing. A custom `Hashable` implementation therefore requires an `Equal` implementation. Matching method names alone never establish either interface.

## Built-in value semantics

`Bool`, `Int`, `Decimal`, `String`, `Bytes`, `Unit`, `Duration`, and `Instant` have built-in equality and hashing implementations. `Never` vacuously satisfies both requirements. Float has IEEE equality, including unequal NaNs and equal positive/negative zero, and has no hashing implementation.

Strings compare exact Unicode scalar sequences without normalization. Bytes compare byte sequences; Decimal compares numeric value. Instants must belong to the same clock domain. Records and alternatives without explicit implementations compare their nominal type and all fields or payloads. These data types satisfy each interface when all their components do. Optional and Result use these rules too.

| Collection | Equality | Hashing |
| --- | --- | --- |
| `List[T]` | Equal corresponding elements in order | Unsupported |
| `Map[K, V]` | Equal associations, independent of insertion order | Unsupported |
| `Set[T]` | Equal members, independent of insertion order | Unsupported |

Structural equality terminates on cyclic data. Collections and recursive data shapes prevent automatic hashing derivation. Recursive values can form mutable cycles; an explicit `Equal`/`Hashable` pair may instead hash a stable domain identity. Functions, resource handles, and service handles have no implicit equality. Interface views expose their declared operations; use `.equals` to compare through an Equal view.

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

These implementations apply to equality operators, collection searches, and key lookup. An equality override disables automatic structural hashing: provide a matching explicit hash before using that type as a key. Implementation visibility follows [ordinary contract rules](contracts.md#coherence-and-visibility), including local extensions and generic specialization.

## Key consistency

For Hashable values, equality must be reflexive, symmetric, and transitive, and equal values must produce equal hashes. Unequal values may collide; equality resolves collisions. Hashes are implementation-dependent lookup aids, not stable IDs or a serialization format.

Keep a stored key's equality and hash behavior unchanged. Remove it before mutating its identity and reinsert afterward. A mutated key is filed under its old hash, so lookups by the old or the new value no longer find it. A custom `hash` is called whenever a key is inserted or looked up. `.clone()` copies outer storage while nested references remain shared. Equality and hash functions should be deterministic and must not depend on authority, resource open state, or wall-clock time.
