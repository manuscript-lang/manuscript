+++
title = "Collections"
weight = 3
+++

# Collections

Use `List[T]` for an ordered sequence, `Map[K, V]` for key/value entries, and `Set[T]` for distinct values. The type arguments state the element, key, and value types. All three collections are mutable references. Assignment retains the same instance; `.clone()` copies its storage.

Import each collection type you name from `@std/collections.ms`. Ordinary bracket list literals also require the canonical `List` import.

| Type | Contents |
| --- | --- |
| `List[T]` | Elements of type `T` |
| `Map[K, V]` | Keys of type `K` and values of type `V` |
| `Set[T]` | Distinct elements of type `T` |

## List literals

Brackets construct mutable lists of values:

```manuscript
let values = [1, 2, 3]
let empty: List[Int] = []
```

The first literal infers `List[Int]`. An empty literal gets its element type from an annotation or the expected parameter type. Every element must match the list's element type; numeric conversions are explicit. Elements evaluate from left to right, and nested lists remain nested.

A function taking `values: List[Int]` is called as `sum(values: [1, 2, 3])` or with an existing list. See [collections as arguments](../functions/declarations-and-calls.md#collections-as-arguments).

## Element requirements

Collections accept any value type, including functions, contract views, builders, and synchronized services. Map keys and set elements additionally require `Hashable`.

Resource and service references may be stored freely. Retaining them does not keep the resource open or register cleanup.

`List[Contract]` stores ordinary contract views. `List[fn(value: Int) -> Int]` stores functions. Both may be passed between tasks without additional bounds. Coordinate shared mutation and reads with `Synchronized`.

Collection applications are invariant. `List[Int]` is not assignable to `List[Float]`; a list inserts neither numeric conversions nor implicit unions of unrelated element types.

```manuscript
let nested: List[List[Int]] = [[], [1, 2]]
# Rejected: incompatible Int and Float elements.
let mixed = [1, 2.0]
# Rejected: no element type can be inferred.
let unknown = []
```

An expected `List[List[Int]]` propagates to the inner literals. Without context, a nonempty literal infers one element type from independently typed elements and checks every element against it. Context-dependent elements such as `none` cannot invent a payload type; another element or enclosing context must determine it. For example `[none, some(value: 1)]` is `List[Optional[Int]]`, while `[none]` without context is rejected.

Collection storage can guard [recursive data](records.md#recursive-data). This does not waive element bounds or confer hashing on the container itself.

## Iteration

Map and set iteration follows insertion order. A [for loop](../control-flow/loops.md) expresses traversal. Ordering within one traversal does not establish an execution order between concurrent operations.

## Mutation and copies

`append`, `prepend`, `with_value`, `without`, `with_values`, `fill`, `copy_within`, and `reverse` update a list and return the same instance. Append reuses available capacity and grows storage when necessary; it does not copy the full list on each call.

Map `with_entry`, `without`, `with_default`, `with_default_from`, `merge`, and `clear` update the receiver. Set `with_value`, `without`, and `clear` update the receiver. Their return values retain that instance for chaining.

```manuscript
let values = [1, 2]
let alias = values
let copy = values.clone()
values.append(3)
# alias now contains [1, 2, 3]; copy still contains [1, 2].
```

Clones have independent outer storage and retain nested references. `map`, `filter`, `slice`, `concat`, `sorted`, and set algebra construct new results. Text and Bytes retain their existing nonmutating operations.

A `for` loop and collection callback traversals snapshot collection membership once; elements retain their references. Adding or removing items inside the body does not change that traversal. Protect shared mutation and concurrent reads with `Synchronized`; every alias must use the same lock.

## Lookup and updates

| Receiver or constructor | Signature/result |
| --- | --- |
| `List[T]` | `length() -> Int`; `at(index: Int) -> Optional[T]` |
| `List[T]` | `append(value: T) -> List[T]`; `concat(values: List[T]) -> List[T]` |
| `Map[K, V]()` | Empty `Map[K, V]` |
| `Map[K, V]` | `length() -> Int`; `get(key: K) -> Optional[V]`; `contains(key: K) -> Bool` |
| `Map[K, V]` | `with_entry(key: K, value: V) -> Map[K, V]`; `without(key: K) -> Map[K, V]` |
| `Set[T]()` | Empty `Set[T]` |
| `Set[T]` | `length() -> Int`; `contains(value: T) -> Bool` |
| `Set[T]` | `with_value(value: T) -> Set[T]`; `without(value: T) -> Set[T]` |

All existing element and key bounds apply. An empty Map/Set constructor requires explicit type arguments or a complete expected application; it supplies no inference evidence by itself. List construction uses the existing bracket literal. List and Bytes `.at` accept relative negative indexes; out-of-range indexes return `none`. A size exceeding MaxInt64 faults.

Maps and sets traverse in insertion order. Replacing an equal map key retains its original key value and first insertion position; adding an existing set element retains its original value and position. Removing an absent key/element is a value-preserving operation. Removing and then adding places the new entry at the end. Equality remains independent of insertion order. Use [builders](../../standard-library/builders.md) for synchronized construction.

```manuscript
import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Optional from "@std/optional.ms"

fn positives(values: List[Int]) -> List[Int]:
    var result: List[Int] = []
    for value in values:
        if value > 0:
            result = result.append(value: value)
    return result

test "dynamic mutable data and explicit copies":
    if not (positives(values: [3, -1, 2]) == [3, 2]):
        return panic(message: "check failed")
    let absent: Optional[Int] = none
    if not ([1].at(index: 5) == absent):
        return panic(message: "check failed")
    let original = Map[String, Int]().with_entry(key: "a", value: 1)
    let updated = original.clone().with_entry(key: "b", value: 2).with_entry(key: "a", value: 3)
    if not (original.get(key: "a") == some(value: 1)):
        return panic(message: "check failed")
    if not (updated.get(key: "a") == some(value: 3)):
        return panic(message: "check failed")
```

## Building data

The [collection reference](../../standard-library/reference/collections.md) lists all methods and constructors. [Builders](../../standard-library/builders.md) provide synchronized construction and sealed builder results.

See [generics and bounds](generics.md) for type arguments and [equality and hashing](equality-and-hashing.md) for key eligibility.
