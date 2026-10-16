+++
title = "Collections"
weight = 3
+++

# Collections

Use `List[T]` for an ordered sequence, `Map[K, V]` for key/value entries, and `Set[T]` for distinct values. The type arguments state the element, key, and value types. All three collections are mutable references. Assignment retains the same instance; `.clone()` copies its storage.

`List`, `Map`, and `Set`, together with their public support types `CollectionError`, `ListEntry[T]`, and `MapEntry[K: Hashable, V]`, are available through the prelude. Use these declarations directly; explicit standard imports of them are rejected. `Optional`, `Result`, `Error`, `MissingValue`, `Equal`, and `Hashable` are also in the prelude, so collection results, callbacks, annotations and bounds need no imports. Builders and factory functions remain explicit imports. See [names and declaration order](../modules/declarations.md#names-and-declaration-order) for the identity and shadowing rules. Literals use the canonical standard types; a module declaration or application import that replaces `List` or `Map` makes its corresponding literal invalid.

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

Entries evaluate in written order, key before value, once each. Equal duplicate keys retain their first insertion position and use the last value, just like `add`. Stored values retain references to nested data. Physical newlines inside braces follow ordinary delimiter continuation rules.

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

`append`, `prepend`, `insert`, `set`, `remove`, `splice`, `fill`, `copy_within`, and `reverse_in_place` update a list and return the same instance. `set(index:, value:)` replaces an element; `remove(index:)` removes one. Both accept negative indexes relative to the end and fault on invalid indexes. `insert(index:, value:)` places a value before `index`, accepting `-length()` through `length()`; `length()` appends, and other indexes fault with the valid range. `pop()` also updates the list: it removes the last element and returns it as `some(value)`, or returns `none` for an empty list. `splice(start:, delete_count:, replacement:)` requires nonnegative bounds with `start <= length()` and `delete_count <= length() - start`; it stages a self-replacement and retains shallow references. Invalid bounds fault without clamping. Append reuses available capacity and grows storage when necessary; it does not copy the full list on each call.

Map `add`, `remove`, `add_default`, `add_default_from`, `merge`, and `clear` update the receiver. Set `add`, `remove`, and `clear` update the receiver. Map `remove` is a no-op for an absent key and keeps scoped lookup and insertion order. Their return values retain that instance for chaining.

```manuscript
let values = [1, 2]
let alias = values
let copy = values.clone()
values.append(3)
# alias now contains [1, 2, 3]; copy still contains [1, 2].
```

Clones have independent outer storage and retain nested references. `map`, `filter`, `slice`, `concat`, `sorted`, `reversed`, and set algebra construct new results. List `reversed()` returns a reversed shallow copy with independent outer storage. Bytes `reversed()` also returns a copy. Text and Bytes retain their existing nonmutating operations.

List `slice` returns `Result[List[T], CollectionError]` and uses strict element bounds after resolving negative bounds relative to the end: `0 <= start <= end <= length()`. Invalid bounds return `CollectionError.OutOfRange`. Successful slices copy outer storage and retain nested references. See the [half-open slice rules](../basics/text-and-bytes.md#half-open-slices) for the distinct String, List, and Bytes contracts.

A List `for` loop or callback traversal evaluates its backing slice and initial length once, without copying or freezing elements. In-place writes can change values read later in that traversal. Append never extends the current traversal. If a mutation reallocates storage, the running traversal keeps its original backing array; shrinking or shifting storage does not reduce its captured length. Use an explicit `.clone()` before traversal when stable, separate outer storage is needed. Nested elements retain their references.

List removal and shrinking replacement shift elements and shorten the receiver's slice without overwriting the vacated tail. A captured traversal can therefore read shifted or repeated prior values. Replacing all elements with an empty list only shortens that slice; later appends can overwrite the same backing storage. Removed references can remain retained in spare capacity until overwritten, reallocated, or released along with the backing array. An explicit `fill` or `copy_within` writes backing elements and can affect later visits.

Map and Set loops and callbacks retain their membership snapshot contract: additions, removals and replacements do not change that traversal. Protect shared mutation and concurrent reads with `Synchronized`; every alias must use the same lock.

### Naming and migration

Use verbs for mutable updates and explicit `.clone()` when a separate mutable result is wanted. `concat`, `filter`, `sorted`, `reversed` and other existing transforms keep their copying contracts; a verb alone does not promise mutation on immutable String or Bytes values. Bytes `with_value` copies byte storage, while Bytes `slice` and `split` may retain immutable views.

The older spellings below were removed because several sounded like copies but mutated their receiver. Replace direct calls and stored method references using this table; argument labels and callable return types stay the same.

| Receiver | Removed spelling | Use | Result |
| --- | --- | --- | --- |
| List | `with_value`, `without`, `with_values`, `reverse` | `set`, `remove`, `splice`, `reverse_in_place` | Same List |
| Map | `with_entry`, `without` | `add`, `remove` | Same Map |
| Map | `with_default`, `with_default_from` | `add_default`, `add_default_from` | Same Map |
| Set | `with_value`, `without` | `add`, `remove` | Same Set |
| MapBuilder | `with_entry` | `add` | Unit |
| SetBuilder | `with_value` | `add` | Unit |
| Bytes | `reverse` | `reversed` | Copy of byte storage |

Map `add_default` evaluates its value argument normally and inserts only when absent. `add_default_from` calls `create(key:)` once only when absent. Neither replaces an existing value or its insertion position. For a copy, write `map.clone().add_default(...)` explicitly.

All [builder mutations](../../standard-library/builders.md) return Unit; `freeze` returns the sealed result. This convention applies to List, Map, Set, Bytes and String builders and preserves their existing function types.

## Primitive storage and memory

Primitive List backing stores each reserved `Int` or `Float` element in 8 bytes,
each `Bool` in 1 byte, and each `String` reference in 16 bytes on a 64-bit host.
String text storage is additional and may be shared. A List also has a small
constant header. Append reserves spare capacity and growth can temporarily keep
old arrays alive, so retained heap and peak process RSS exceed the element budget.
Int remains the platform-sized signed integer and Float remains binary64; storage does not narrow values.

Passing a List through a generic function, record, Optional, Result, closure, or
stored operation preserves its mutable identity and backing kind. Generic access
boxes a primitive only when it crosses the ordinary value boundary. Explicit
copies preserve shallow references and receive independent backing.

See [Go representation](../../contributing/go-lowering-representation.md) for Go callers
and the measured constructor/access/comparator paths.

## Lookup and updates

| Receiver or constructor | Signature/result |
| --- | --- |
| `List[T]()` | Empty `List[T]` |
| `List[T]` | `length() -> Int`; `at(index: Int) -> Optional[T]`; `[index] -> Optional[T]` |
| `List[T]` | `append(value: T) -> List[T]`; `concat(values: List[T]) -> List[T]` |
| `List[T]` | `set(index: Int, value: T) -> List[T]`; `remove(index: Int) -> List[T]` |
| `List[T]` | `insert(index: Int, value: T) -> List[T]`; `pop() -> Optional[T]` |
| `Map[K, V]()` | Empty `Map[K, V]` |
| `Map[K, V]` | `length() -> Int`; `get(key: K) -> Optional[V]`; `contains(key: K) -> Bool` |
| `Map[K, V]` | `is_empty() -> Bool`; `get_or(key: K, fallback: V) -> V` |
| `Map[K, V]` | `filter(predicate: fn(key: K, value: V) -> Bool) -> Map[K, V]` |
| `Map[K, V]` | `map[W](transform: fn(key: K, value: V) -> W) -> Map[K, W]` |
| `Map[K, V]` | `map_keys[W: Hashable](transform: fn(key: K, value: V) -> W) -> Map[W, V]` |
| `Map[K, V]` | `fold[A](initial: A, step: fn(accumulator: A, key: K, value: V) -> A) -> A` |
| `Map[K, V]` | `fold_right[A]` uses the same step in reverse insertion order |
| `Map[K, V]` | `find(predicate: fn(key: K, value: V) -> Bool) -> Optional[MapEntry[K, V]]` |
| `Map[K, V]` | `find_last` uses the same predicate and entry result, searching from the end |
| `Map[K, V]` | `some(predicate: fn(key: K, value: V) -> Bool) -> Bool`; `every` uses the same predicate |
| `Map[K, V]` | `add(key: K, value: V) -> Map[K, V]`; `remove(key: K) -> Map[K, V]` |
| `Set[T]()` | Empty `Set[T]` |
| `Set[T]` | `length() -> Int`; `contains(value: T) -> Bool` |
| `Set[T]` | `is_empty() -> Bool`; `filter(predicate: fn(value: T) -> Bool) -> Set[T]` |
| `Set[T]` | `map[U: Hashable](transform: fn(value: T) -> U) -> Set[U]` |
| `Set[T]` | `add(value: T) -> Set[T]`; `remove(value: T) -> Set[T]` |
| `Set[T]` | `fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A` |
| `Set[T]` | `fold_right[A]` uses the same step in reverse insertion order |
| `Set[T]` | `find(predicate: fn(value: T) -> Bool) -> Optional[T]` |
| `Set[T]` | `find_last` uses the same predicate and payload result, searching from the end |
| `Set[T]` | `some(predicate: fn(value: T) -> Bool) -> Bool`; `every` uses the same predicate |

All existing element and key bounds apply. An empty List/Map/Set constructor requires explicit type arguments or a complete expected application; it supplies no inference evidence by itself. Each call creates fresh storage. Lists also support bracket literals. `values[index]` is equivalent to `values.at(index)`: both return `Optional[T]`, accept relative negative indexes, and return `none` out of range. For example, `values[0].unwrap_or(0)` supplies a default without a separate length check. Bytes `.at` also accepts relative negative indexes and returns `none` out of range. A size exceeding MaxInt64 faults.

`Map.add(key, value)` inserts or replaces a value and returns the same map.

Maps and sets traverse in insertion order. Replacing an equal map key retains its original key value and first insertion position; adding an existing set element retains its original value and position. Removing an absent key/element is a value-preserving operation. Removing and then adding places the new entry at the end. Equality remains independent of insertion order. Use [builders](../../standard-library/builders.md) for synchronized construction.

Map `get`, `contains`, and `add` and Set `contains` and `add` look keys up by hash, so they take constant time on average for built-in keys and for records whose fields hash. Map and Set `remove` keep insertion order by shifting later entries in memory, without re-indexing them, so removal costs a fast copy proportional to the collection size rather than a re-hash. List `contains` and `index_of` compare elements one by one. A key that is mutated in place while stored becomes unreachable by its old and new values; remove it before mutating it, or store a `.clone()`. See [key consistency](equality-and-hashing.md#key-consistency).

### Search and enumeration

| Operation | Result |
| --- | --- |
| List `index_of(value:)`, `last_index_of(value:)` | First or last equal element's zero-based index, or `none`; these searches require `Equal` elements. |
| List `find_index(predicate:)`, `find_last_index(predicate:)` | First or last matching index, or `none`. `find` and `find_last` return the matching value instead. |
| List `count(predicate:)` | Number of elements whose predicate returns true, calling it once per element in order. |
| List `distinct()` | A new list keeping the first of each group of equal elements in original order; requires `Equal` elements. |
| List `keys()`, `entries()` | A new list of indexes, or `List[ListEntry[T]]` records containing `index` and `value`. |
| Map `keys()`, `values()`, `entries()` | New lists in insertion order; entries are `MapEntry[K, V]` records with `key` and `value`. |
| Set `values()`, `entries()` | New lists in insertion order; `entries()` returns `List[List[T]]`, with each inner list `[value, value]`. |
| List/Set `for_each(operation:)` | Calls `operation(value:)` sequentially for each value; returns Unit. |
| Map `for_each(operation:)` | Calls `operation(key:, value:)` sequentially for each entry; returns Unit. |

Enumeration copies outer storage and retains nested references. List callbacks use the captured backing slice described above; Map and Set callbacks use membership snapshots.

Set `union`, `intersection`, `difference`, and `symmetric_difference` return new sets. Symmetric difference contains values present in exactly one operand. `is_subset_of` tests whether all receiver values occur in the right operand, `is_superset_of` tests the converse, and `is_disjoint_from` tests whether there are no common values. The empty set is a subset of every set and is disjoint from every set. These operations leave both operands unchanged.

```manuscript
import panic from "@std/faults.ms"


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
    let original = Map[String, Int]().add(key: "a", value: 1)
    let updated = original.clone().add(key: "b", value: 2).add(key: "a", value: 3)
    if not (original.get(key: "a") == some(1)):
        return panic(message: "check failed")
    if not (updated.get(key: "a") == some(3)):
        return panic(message: "check failed")
```

Map `get_or` evaluates its fallback as an ordinary argument and never inserts an absent key. Map and Set `filter` return fresh outer storage in insertion order while retaining key and payload references. Their predicates visit a snapshot, so additions, removals, replacements, and clearing during a callback do not change which entries it receives. An empty result still has independent storage.

Set `map` also visits a snapshot and returns a fresh set. Its output type must satisfy `Hashable`; equal mapped results retain the first payload and its insertion position. Deduplication uses the output type's scoped Equal/Hashable implementations, including in generic calls and stored methods. Callbacks run sequentially in the caller's execution context; faults and cancellation stop the traversal normally.

## Transforming Map keys and values

`map` transforms each value while retaining the original key. `map_keys` transforms each key while retaining the original value; its output keys require Hashable. Both callbacks receive `key` and `value`, visit an insertion-order membership snapshot, and return fresh outer Map storage with shallow payload references. Callback mutation does not change which source entries or value references are visited.

Equal transformed keys retain the first transformed key reference and insertion position, while later input entries replace its value, matching ordinary Map insertion. Key deduplication uses the output type's scoped Equal/Hashable evidence, including generic forwarding and stored specialized methods. Callback faults and cancellation propagate normally. Value transforms do not flatten Optional or Result values and do not require output values to be Hashable.

```manuscript
fn increment_scores(scores: Map[String, Int]) -> Map[String, Int]:
    return scores.map(fn(name, score): score + 1)
```

## Reducing and querying

Map and Set `fold` visit a snapshot in insertion order. The callback receives the current accumulator, then the entry key/value or set element, and returns the next accumulator with the same type `A`. An empty receiver returns the original initial value without calling the step. Accumulators and payloads retain their references.

`fold_right` uses the same callback and accumulator contract in reverse insertion order. It starts with the final inserted entry/element and moves toward the first. Empty receivers return the original initial value without invoking callbacks.

`find` stops at the first true predicate. Set returns the original element; Map returns a fresh MapEntry record with the original key/value references, matching `entries()`. Replacing that record's fields does not update the Map. No match, including an empty receiver, returns none.

`find_last` visits the snapshot in reverse insertion order and stops at the first true predicate from the end. It retains the same Optional and shallow payload/entry contracts as `find`; a nonmatching search visits the complete snapshot in reverse.

`some` stops at the first true predicate; `every` stops at the first false predicate. Empty receivers return false for some and true for every without invoking callbacks. All four methods snapshot membership before callbacks, retaining shallow references even if the callback updates or clears the receiver. They preserve normal cancellation, faults, and scoped generic implementation evidence.

## Building data

The [collection reference](../../standard-library/reference/collections.md) lists all methods and constructors. [Builders](../../standard-library/builders.md) provide synchronized construction and sealed builder results.

See [generics and bounds](generics.md) for type arguments and [equality and hashing](equality-and-hashing.md) for key eligibility.
