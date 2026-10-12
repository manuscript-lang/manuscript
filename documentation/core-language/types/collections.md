+++
title = "Collections"
weight = 15
+++

# Collections

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use `List[T]` for an ordered sequence, `Map[K, V]` for key/value entries, and `Set[T]` for distinct values. The type arguments state the element, key, and value types. All three collections are immutable.

Import each collection type you name from `@std/collections.ms`. Ordinary bracket list literals also require the canonical `List` import.

| Type | Contents |
| --- | --- |
| `List[T]` | Elements of type `T` |
| `Map[K, V]` | Keys of type `K` and values of type `V` |
| `Set[T]` | Distinct elements of type `T` |

## List literals

Brackets construct immutable lists of values:

```manuscript
let values = [1, 2, 3]
let empty: List[Int] = []
```

The first literal infers `List[Int]`. An empty literal gets its element type from an annotation or the expected parameter type. Every element must match the list's element type; numeric conversions are explicit. Elements evaluate from left to right, and nested lists remain nested.

A function taking `values: List[Int]` is called as `sum(values: [1, 2, 3])` or with an existing list. See [collections as arguments](../functions/declarations-and-calls.md#collections-as-arguments).

## Element requirements

Collections accept any value type, including functions, contract views, builders, and synchronized services. Map keys and set elements additionally require `Hashable`.

Resource and service references may be stored freely. Retaining them does not keep the resource open or register cleanup.

`List[Contract]` stores ordinary contract views. `List[fn(value: Int) -> Int]` stores functions. Both may be used concurrently without additional bounds.

Collection applications are invariant. `List[Int]` is not assignable to `List[Float]`; a list inserts neither numeric conversions nor implicit unions of unrelated element types.

```manuscript
let nested: List[List[Int]] = [[], [1, 2]]
# Rejected: incompatible Int and Float elements.
let mixed = [1, 2.0]
# Rejected: no element type can be inferred.
let unknown = []
```

An expected `List[List[Int]]` propagates to the inner literals. Without context, a nonempty literal infers one element type from independently typed elements and checks every element against it. Context-dependent elements such as `none` cannot invent a payload type; another element or enclosing context must determine it. For example `[none, some(value: 1)]` is `List[Optional[Int]]`, while `[none]` without context is rejected.

Immutable containers can guard [recursive data](records.md#recursive-data). This does not waive element bounds or confer hashing on the container itself.

## Iteration

Map and set iteration follows insertion order. A [for loop](../control-flow/loops.md) expresses traversal. Ordering within one traversal does not establish an execution order between concurrent operations.

## Building data

Use the [data API](../../standard-library/data-and-io/operations.md#collections) for construction, lookup, and immutable updates. [Builders](../../standard-library/data-and-io/builders.md) provide synchronized construction and sealed immutable snapshots.

See [generics and bounds](generics.md) for type arguments and [equality and hashing](equality-and-hashing.md) for key eligibility.

[Previous: Optional values](optionals.md) · [Next: Equality and hashing](equality-and-hashing.md)
