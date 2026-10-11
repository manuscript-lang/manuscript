+++
title = "Collections"
weight = 15
+++

# Collections

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The standard module `@std/collections.ms` exports `List[T]`, `Map[K, V]`, and `Set[T]` as immutable collections. Import each name used by the module; ordinary bracket literals also require the canonical List import. Their type arguments describe the elements, keys, and values.

| Type | Contents |
| --- | --- |
| `List[T]` | Elements of type `T` |
| `Map[K, V]` | Keys of type `K` and values of type `V` |
| `Set[T]` | Distinct elements of type `T` |

## List literals

Brackets construct immutable lists of shareable values:

```text
let values = [1, 2, 3]
let empty: List[Int] = []
```

The first literal infers `List[Int]`. An empty literal gets its element type from an annotation or the expected parameter type. Every element must match the list's element type; numeric conversions are explicit. Elements evaluate from left to right, and nested lists remain nested.

A function taking `values: List[Int]` is called as `sum(values: [1, 2, 3])` or with an existing list. See [collections as arguments](../functions/declarations-and-calls.md#collections-as-arguments).

## Element requirements

Collections require shareable elements; map keys and set elements additionally require hashing. A map's keys and values must therefore be shareable, and its keys must also satisfy the hashing requirement.

Resource and service references may be stored when they meet the element sharing bounds. Retaining them does not keep the resource open or register cleanup. Dynamic concurrent traversal uses [parallel_map](../../standard-library/tasks/parallel-map.md).

Interface elements must retain a static sharing guarantee: `List[Contract & Shareable]` is permitted, while `List[Contract]` fails its element bound even when every hidden receiver happens to be shareable. Construct [shared contract views](contracts.md#shared-contract-views) before inserting them.

Collection applications are invariant. `List[Int]` is not assignable to `List[Float]`; a list inserts neither numeric conversions nor implicit unions of unrelated element types.

```text
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

Use the [data API](../../standard-library/data-and-io/operations.md#collections) for construction, lookup, and immutable updates. [Builders](../../standard-library/data-and-io/builders.md) describe mutable construction, but their callable API is still incomplete.

See [generics and bounds](generics.md) for type arguments and [equality and hashing](equality-and-hashing.md) for key eligibility.

[Previous: Optional values](optionals.md) · [Next: Equality and hashing](equality-and-hashing.md)
