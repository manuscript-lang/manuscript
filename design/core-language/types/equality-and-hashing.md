+++
title = "Equality and hashing"
weight = 16
+++

# Equality and hashing

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Equality compares eligible values by their contents. Hashing is the additional property needed to use a value as a map key or set element. The compiler checks these properties from the type. Services, resources, and capabilities do not gain equality automatically.

Equality is by value for eligible shareable data types; services, resources, and capabilities have no implicit equality.

## Eligibility and value behavior

`Bool`, `Int`, `Decimal`, `String`, `Bytes`, `Unit`, `Duration`, and `Instant` support equality and hashing. `Never` vacuously meets both bounds but has no constructible value. `Float` supports IEEE 754 equality: NaN compares unequal to every value, including itself, and positive and negative zero compare equal. `Float` is not `Hashable`.

String equality compares exact UTF-8 scalar sequences without Unicode normalization. Bytes compare byte sequences. Decimal equality compares numeric value rather than spelling or trailing zeroes. Hashing must agree with equality: equal values have equal hashes, but unequal values may collide. Hash values/algorithms are not a stable serialized format or a public source operation.

Records compare only with the same instantiated nominal type, field by field. Alternatives require the same instantiated type, tag, and equal payload fields. A record/alternative is `Equal` when every component is eligible for equality, and `Hashable` when every component is eligible for hashing. Optional and Result follow these alternative rules. Derivations respect current sharing eligibility and do not grant equality to service/resource references.

| Collection | Equality | Hashing |
| --- | --- | --- |
| `List[T]` | Same length and equal corresponding elements; requires `T: Equal` | Unsupported |
| `Map[K, V]` | Same key/value associations regardless of insertion order; requires eligible keys and `V: Equal` | Unsupported |
| `Set[T]` | Same members regardless of insertion order; requires eligible elements | Unsupported |

Collections are not `Hashable`. A record containing a collection can be `Equal` but cannot automatically become a map key or set element. Function values and contract views have no implicit equality or hashing.

```text
let same = [1, 2] == [1, 2]
let different = [1, 2] == [2, 1]  # false
# Rejected at type checking: Float is not Hashable.
fn accepts_float_keys(values: Map[Float, Int]) -> Unit:
    return
```

For [guarded recursive data](records.md#recursive-data), eligibility is checked over the finite declaration graph. Every nonrecursive leaf must meet the bound; recursive references reuse the requirement already being checked. A cycle does not establish eligibility if a leaf fails it. Generated equality traverses finite immutable values structurally. Containers still block hashing derivation even when they guard recursive layout.

```text
type Tree[T: Equal]:
    value: T
    children: List[Tree[T]]
```

This tree is `Equal` for eligible `T`; its list field prevents hashing. User-defined implementations of compiler bounds cannot override these derivations.

## Compiler-defined bounds

`Equal` and `Hashable` are compiler-defined bounds. Hashing requires equality. A generic operation can require these properties using a [bound](generics.md), and the compiler checks whether its type arguments meet the requirement.

| Use | Requirements |
| --- | --- |
| Value equality | Eligible shareable data type with equality |
| `Map[K, V]` key | Shareable and hashable, including equality |
| `Set[T]` element | Shareable and hashable, including equality |

## Equality and hash consistency

For a Hashable type, equality must be reflexive, symmetric, and transitive. Equal values must hash identically under the same hash configuration. Unequal values may have the same hash; a map or set must resolve every collision by equality rather than accepting a hash match as a key match. Hashes are internal lookup aids, not stable IDs or persistence formats.

The same immutable key must retain its equality and hash behavior while stored. Neither operation depends on a resource's open state, external authority, insertion order, or current wall-clock time. Float and records containing Float remain equality-comparable with IEEE behavior, but cannot meet Hashable's equivalence requirement because NaN is not equal to itself.

With structural derivation, every declared field participates. A display label or cached value is not silently excluded. Model a lookup identity as its own record, then use that record as the key:

```text
import panic from "@std/faults.ms"

import Map from "@std/collections.ms"

type CustomerKey:
    id: String

type Customer:
    key: CustomerKey
    display_name: String

test "domain identity is a value":
    let first = Customer(key: CustomerKey(id: "c1"), display_name: "Ada")
    let renamed = Customer(key: CustomerKey(id: "c1"), display_name: "Ada Lovelace")
    if not (first != renamed):
        return panic(message: "check failed")
    if not (first.key == renamed.key):
        return panic(message: "check failed")
    let names = Map[CustomerKey, String]().with_entry(key: first.key, value: first.display_name)
    let updated = names.with_entry(key: renamed.key, value: renamed.display_name)
    if not (updated.length() == 1):
        return panic(message: "check failed")
```

A domain requiring normalized text identity should construct a canonical key value explicitly. String equality itself remains exact; adding a matching operation name to a type does not change `==` or key lookup.

## Domain values and runtime authority

A [nominal record](records.md) describes domain data. Capabilities describe external authority, and a `Background` service controls work under a fixed lifetime. Safe concurrent sharing does not automatically grant equality to a service or resource.

The [compiler](../../compiler/lowering/value-representations.md) generates equality and hashing operations for eligible types. The design does not introduce arbitrary user-defined operator overloading.

[Previous: Collections](collections.md) · [Next: Operation contracts](contracts.md)
