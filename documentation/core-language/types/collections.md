+++
title = "Collections"
weight = 3
+++

# Collections

Use `List[T]` for an ordered sequence, `Map[K, V]` for key/value entries, and `Set[T]` for distinct values. The type arguments state the element, key, and value types. All three collections are mutable references. Assignment retains the same instance; `.clone()` copies its storage.

Import each collection type you name from `@std/collections.ms`. Bracket list literals require the canonical `List` import; brace map literals require the canonical `Map` import.

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
let also_empty = List[Int]()
```

The first literal infers `List[Int]`. An empty literal gets its element type from an annotation or the expected parameter type. Every element must match the list's element type; numeric conversions are explicit. Elements evaluate from left to right, and nested lists remain nested.

A function taking `values: List[Int]` is called as `sum(values: [1, 2, 3])` or with an existing list. See [collections as arguments](../functions/declarations-and-calls.md#collections-as-arguments).

## Map literals

Braces construct mutable maps:

```manuscript
let scores = {"Ada": 3, "Lin": 5}
let empty: Map[String, Int] = {}
```

Write each entry as `key: value`, with optional trailing commas. Keys are expressions: `{name: score}` uses the value of `name`, while `{"name": score}` uses a String key. Bare names do not become String keys. Map literals construct Maps, not record instances.

A nonempty literal infers key and value types independently from its entries. Expected Map types propagate to both keys and values, including nested empty literals. An empty map needs an annotation or expected parameter/return type. Every key and value must match its inferred or expected type; keys must satisfy `Hashable`.

Entries evaluate in written order, key before value, once each. Equal duplicate keys retain their first insertion position and use the last value, just like `with_entry`. Stored values retain references to nested data. Physical newlines inside braces follow ordinary delimiter continuation rules.

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

Collections can hold [recursive data](records.md#recursive-data). Element bounds still apply, and the containers do not derive hashing.

## Iteration

Map and set iteration follows insertion order. A [for loop](../control-flow/loops.md) expresses traversal. Ordering within one traversal does not establish an execution order between concurrent operations.

## Mutation and copies

`append`, `prepend`, `set`, `remove`, `with_values`, `fill`, `copy_within`, and `reverse` update a list and return the same instance. `set(index:, value:)` replaces an element; `remove(index:)` removes one. Both accept negative indexes relative to the end and fault on invalid indexes. `with_value` and `without` remain compatible spellings for `set` and `remove`, with the same receiver returns and faults. Append reuses available capacity and grows storage when necessary; it does not copy the full list on each call.

Map `with_entry`, `without`, `with_default`, `with_default_from`, `merge`, and `clear` update the receiver. Set `add`, `remove`, and `clear` update the receiver; `with_value` and `without` remain compatible spellings for `add` and `remove`. Their return values retain that instance for chaining.

```manuscript
let values = [1, 2]
let alias = values
let copy = values.clone()
values.append(3)
# alias now contains [1, 2, 3]; copy still contains [1, 2].
```

Clones have independent outer storage and retain nested references. `map`, `filter`, `slice`, `concat`, `sorted`, and set algebra construct new results. Text and Bytes retain their existing nonmutating operations.

List `slice` uses strict, nonnegative element bounds: `0 <= start <= end <= length()`. Invalid bounds fault; negative indexes accepted by `at` are not accepted by `slice`. See the [half-open slice rules](../basics/text-and-bytes.md#half-open-slices) for the distinct String, List, and Bytes contracts.

A `for` loop and collection callback traversals snapshot collection membership once; elements retain their references. Adding or removing items inside the body does not change that traversal. Protect shared mutation and concurrent reads with `Synchronized`; every alias must use the same lock.

## Lookup and updates

| Receiver or constructor | Signature/result |
| --- | --- |
| `List[T]()` | Empty `List[T]` |
| `List[T]` | `length() -> Int`; `at(index: Int) -> Optional[T]`; `[index] -> Optional[T]` |
| `List[T]` | `append(value: T) -> List[T]`; `concat(values: List[T]) -> List[T]` |
| `List[T]` | `set(index: Int, value: T) -> List[T]`; `remove(index: Int) -> List[T]` |
| `Map[K, V]()` | Empty `Map[K, V]` |
| `Map[K, V]` | `length() -> Int`; `get(key: K) -> Optional[V]`; `contains(key: K) -> Bool` |
| `Map[K, V]` | `is_empty() -> Bool`; `get_or(key: K, fallback: V) -> V` |
| `Map[K, V]` | `filter(predicate: fn(key: K, value: V) -> Bool) -> Map[K, V]` |
| `Map[K, V]` | `fold[A](initial: A, step: fn(accumulator: A, key: K, value: V) -> A) -> A` |
| `Map[K, V]` | `find(predicate: fn(key: K, value: V) -> Bool) -> Optional[MapEntry[K, V]]` |
| `Map[K, V]` | `some(predicate: fn(key: K, value: V) -> Bool) -> Bool`; `every` uses the same predicate |
| `Map[K, V]` | `with_entry(key: K, value: V) -> Map[K, V]`; `without(key: K) -> Map[K, V]` |
| `Set[T]()` | Empty `Set[T]` |
| `Set[T]` | `length() -> Int`; `contains(value: T) -> Bool` |
| `Set[T]` | `is_empty() -> Bool`; `filter(predicate: fn(value: T) -> Bool) -> Set[T]` |
| `Set[T]` | `map[U: Hashable](transform: fn(value: T) -> U) -> Set[U]` |
| `Set[T]` | `add(value: T) -> Set[T]`; `remove(value: T) -> Set[T]` |
| `Set[T]` | `fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A` |
| `Set[T]` | `find(predicate: fn(value: T) -> Bool) -> Optional[T]` |
| `Set[T]` | `some(predicate: fn(value: T) -> Bool) -> Bool`; `every` uses the same predicate |

All existing element and key bounds apply. An empty List/Map/Set constructor requires explicit type arguments or a complete expected application; it supplies no inference evidence by itself. Each call creates fresh storage. Lists also support bracket literals. `values[index]` is equivalent to `values.at(index)`: both return `Optional[T]`, accept relative negative indexes, and return `none` out of range. For example, `values[0].unwrap_or(0)` supplies a default without a separate length check. Bytes `.at` also accepts relative negative indexes and returns `none` out of range. A size exceeding MaxInt64 faults.

Maps and sets traverse in insertion order. Replacing an equal map key retains its original key value and first insertion position; adding an existing set element retains its original value and position. Removing an absent key/element is a value-preserving operation. Removing and then adding places the new entry at the end. Equality remains independent of insertion order. Use [builders](../../standard-library/builders.md) for synchronized construction.

Map `get`, `contains`, and `with_entry` and Set `contains` and `add` look keys up by hash, so they take constant time on average for built-in keys and for records whose fields hash. Map `without` and Set `remove` shift later entries to keep insertion order and take time proportional to the collection size. List `contains` and `index_of` compare elements one by one. A key that is mutated in place while stored becomes unreachable by its old and new values; remove it before mutating it, or store a `.clone()`. See [key consistency](equality-and-hashing.md#key-consistency).

### Search and enumeration

| Operation | Result |
| --- | --- |
| List `index_of(value:)`, `last_index_of(value:)` | First or last equal element's zero-based index, or `none`; these searches require `Equal` elements. |
| List `find_index(predicate:)`, `find_last_index(predicate:)` | First or last matching index, or `none`. `find` and `find_last` return the matching value instead. |
| List `keys()`, `entries()` | A new list of indexes, or `List[ListEntry[T]]` records containing `index` and `value`. |
| Map `keys()`, `values()`, `entries()` | New lists in insertion order; entries are `MapEntry[K, V]` records with `key` and `value`. |
| Set `values()`, `entries()` | New lists in insertion order; `entries()` returns `List[List[T]]`, with each inner list `[value, value]`. |
| List/Set `for_each(operation:)` | Calls `operation(value:)` sequentially for each value; returns Unit. |
| Map `for_each(operation:)` | Calls `operation(key:, value:)` sequentially for each entry; returns Unit. |

Enumeration copies outer storage and retains nested references. Callback traversals use the membership snapshot described above.

Set `union`, `intersection`, `difference`, and `symmetric_difference` return new sets. Symmetric difference contains values present in exactly one operand. `is_subset_of` tests whether all receiver values occur in the right operand, `is_superset_of` tests the converse, and `is_disjoint_from` tests whether there are no common values. The empty set is a subset of every set and is disjoint from every set. These operations leave both operands unchanged.

```manuscript
import panic from "@std/faults.ms"

import List from "@std/collections.ms"
import Map from "@std/collections.ms"

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
    if not (original.get(key: "a") == some(1)):
        return panic(message: "check failed")
    if not (updated.get(key: "a") == some(3)):
        return panic(message: "check failed")
```

Map `get_or` evaluates its fallback as an ordinary argument and never inserts an absent key. Map and Set `filter` return fresh outer storage in insertion order while retaining key and payload references. Their predicates visit a snapshot, so additions, removals, replacements, and clearing during a callback do not change which entries it receives. An empty result still has independent storage.

Set `map` also visits a snapshot and returns a fresh set. Its output type must satisfy `Hashable`; equal mapped results retain the first payload and its insertion position. Deduplication uses the output type's scoped Equal/Hashable implementations, including in generic calls and stored methods. Callbacks run sequentially in the caller's execution context; faults and cancellation stop the traversal normally.

## Reducing and querying

Map and Set `fold` visit a snapshot in insertion order. The callback receives the current accumulator, then the entry key/value or set element, and returns the next accumulator with the same type `A`. An empty receiver returns the original initial value without calling the step. Accumulators and payloads retain their references.

`find` stops at the first true predicate. Set returns the original element; Map returns a fresh MapEntry record with the original key/value references, matching `entries()`. Replacing that record's fields does not update the Map. No match, including an empty receiver, returns none.

`some` stops at the first true predicate; `every` stops at the first false predicate. Empty receivers return false for some and true for every without invoking callbacks. All four methods snapshot membership before callbacks, retaining shallow references even if the callback updates or clears the receiver. They preserve normal cancellation, faults, and scoped generic implementation evidence.

## Building data

The [collection reference](../../standard-library/reference/collections.md) lists all methods and constructors. [Builders](../../standard-library/builders.md) provide synchronized construction and sealed builder results.

See [generics and bounds](generics.md) for type arguments and [equality and hashing](equality-and-hashing.md) for key eligibility.
