+++
title = "Collections"
weight = 3
+++

# Collections

Collections are owned values. Consuming uses move them at their last use; local place bindings and accessors can borrow them. `.clone()` makes an explicit deep copy. Mutation requires `var`; see [mutation and references](references.md).

`List`, `Map`, `Set`, `CollectionError`, `ListEntry[T]`, and `MapEntry[K: Hashable, V]` are prelude names (with `Optional`, `Result`, `Error`, `MissingValue`, `Equal`, `Hashable`); importing them is rejected. Builders and factories need imports. See [names and declaration order](../modules/declarations.md#names-and-declaration-order).

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

The first literal infers `List[Int]`; an empty literal needs an annotation or expected type. Every element must match the element type (no implicit numeric conversion) and evaluates left to right. See [collections as arguments](../functions/declarations-and-calls.md#collections-as-arguments).

## Map literals

Braces construct mutable maps:

```manuscript
let scores = {"Ada": 3, "Lin": 5}
let empty: Map[String, Int] = {}
```

Entries are `key: value`, trailing commas allowed. Keys are expressions: `{name: score}` uses the value of `name`; `{"name": score}` uses a String. Map literals never construct records.

- A nonempty literal infers key and value types independently; an expected Map type propagates to both. An empty map needs an annotation or expected type.
- Keys must be `Hashable`.
- Entries evaluate once, in written order, key before value.
- Duplicate keys keep their first position and last value, like `add`.

## Element requirements

Collections accept any value type (functions, contract views, builders, services, resources); storing a resource neither keeps it open nor registers cleanup. Map keys and set elements also require `Hashable`.

Applications are invariant: `List[Int]` is not a `List[Float]`, and no implicit unions or numeric conversions apply.

```manuscript
let nested: List[List[Int]] = [[], [1, 2]]
# Rejected: incompatible Int and Float elements.
let mixed = [1, 2.0]
# Rejected: no element type can be inferred.
let unknown = []
```

An expected type propagates into inner literals. Without one, elements must agree on one type; `none` needs another element or context to fix its payload, so `[none, some(value: 1)]` is `List[Optional[Int]]` and `[none]` is rejected. Collections can hold [recursive data](records.md#recursive-data) but derive no hashing.

## Iteration

Maps and sets iterate in insertion order, with a [for loop](../control-flow/loops.md).

## Mutation and copies

Mutators update the receiver in place and return Unit; a `let` binding cannot be mutated, so declare the collection with `var`.

- List: `append`, `prepend`, `insert`, `set`, `remove`, `splice`, `fill`, `copy_within`, `reverse_in_place`.
- Map: `add`, `remove`, `add_default`, `add_default_from`, `merge`, `clear`. Removing an absent key is a no-op.
- Set: `add`, `remove`, `clear`.

List details:

- `set(index:, value:)` and `remove(index:)` accept negative indexes and fault on invalid ones.
- `insert(index:, value:)` places before `index`, valid from `-length()` to `length()` (which appends).
- `pop()` returns the last element as `some(value)`, or `none` when empty.
- `splice(start:, delete_count:, replacement:)` needs `0 <= start <= length()` and `delete_count <= length() - start`.
- Invalid bounds fault; nothing is clamped.

```manuscript
var values = [1, 2]
let copy = values.clone()
values.append(3)
# values now contains [1, 2, 3]; copy still contains [1, 2].
```

Clones copy nested values too. `map`, `filter`, `slice`, `concat`, `sorted`, `reversed`, and set algebra return independent owned results (Bytes `reversed()` too).

List `slice` returns `Result[List[T], CollectionError]` with strict bounds `0 <= start <= end <= length()` after resolving negative bounds from the end; otherwise `CollectionError.OutOfRange`. See the [half-open slice rules](../basics/text-and-bytes.md#half-open-slices).

A collection loop or non-escaping callback borrows the receiver for the traversal. The checker rejects mutation, reassignment, or a move of that receiver while the borrow is live. To mutate the original while traversing independent data, make an explicit `.clone()` first.

### Naming and migration

Verbs mutate; use `.clone()` for a separate result. Transforms such as `concat`, `filter`, `sorted`, and `reversed` copy. Bytes `with_value` copies, while Bytes `slice` and `split` may retain immutable views.

These removed spellings looked like copies but mutated. Labels and return types are unchanged.

| Receiver | Removed spelling | Use | Result |
| --- | --- | --- | --- |
| List | `with_value`, `without`, `with_values`, `reverse` | `set`, `remove`, `splice`, `reverse_in_place` | Same List |
| Map | `with_entry`, `without` | `add`, `remove` | Same Map |
| Map | `with_default`, `with_default_from` | `add_default`, `add_default_from` | Same Map |
| Set | `with_value`, `without` | `add`, `remove` | Same Set |
| MapBuilder | `with_entry` | `add` | Unit |
| SetBuilder | `with_value` | `add` | Unit |
| Bytes | `reverse` | `reversed` | Copy of byte storage |

`List.shift` is removed. Use `Queue` (`enqueue`, `dequeue`, `peek`) for first-in, first-out work: `dequeue` is O(1), where `shift` cost O(n) per call. Use `Deque` when values are pushed or popped at both ends.

Map `add_default` evaluates its argument and inserts only when absent; `add_default_from` calls `create(key:)` once, only when absent. Neither replaces an existing value or position. Copy first with `map.clone().add_default(...)`.

Builder mutations return Unit; `freeze` returns the sealed result.

## Other collections

The standard library adds collections written in Manuscript. Each follows value ownership: use `.clone()` for an independent deep copy. Find exact signatures with `ms search_symbol <name>`.

| Type | Use it for |
| --- | --- |
| `Queue[T]` | First-in, first-out work, optionally bounded; `PriorityQueue[T]` orders by a compare function with FIFO ties |
| `Deque[T]` | A queue with O(1) amortized push and pop at both ends and O(1) indexed reads, such as sliding windows |
| `BitSet` | Dense sets of small non-negative integers (0 through 1073741823), one bit each |
| `SortedMap[K, V]`, `SortedSet[T]` | Ascending key order with first, last, floor, ceiling, and range lookups; keys must be `Comparable` |

Use `Map` and `Set` when order does not matter; their lookups are O(1) on average.

## Primitive storage and memory

On a 64-bit host a List reserves 8 bytes per `Int` or `Float`, 1 per `Bool`, and 16 per `String` reference (text storage is extra and may be shared), plus a small header. Append reserves spare capacity and growth can briefly keep old arrays alive, so heap and peak RSS exceed the element budget. Storage never narrows `Int` or `Float`.

A List keeps its identity and backing kind through generics, records, Optional, Result, and closures; explicit copies get independent backing.

## Lookup and updates

| Receiver or constructor | Signature/result |
| --- | --- |
| `List[T]()` | Empty `List[T]` |
| `List[T]` | `length() Int`; `get(index: Int, default: Optional[T] = none) T`; `[index] T` |
| `List[T]` | `append(value: T) List[T]`; `concat(values: List[T]) List[T]` |
| `List[T]` | `set(index: Int, value: T) List[T]`; `remove(index: Int) List[T]` |
| `List[T]` | `insert(index: Int, value: T) List[T]`; `pop() Optional[T]` |
| `Map[K, V]()` | Empty `Map[K, V]` |
| `Map[K, V]` | `length() Int`; `get(key: K) Optional[V]`; `contains(key: K) Bool` |
| `Map[K, V]` | `is_empty() Bool`; `get_or(key: K, fallback: V) V` |
| `Map[K, V]` | `filter(predicate: fn(key: K, value: V) Bool) Map[K, V]` |
| `Map[K, V]` | `map[W](transform: fn(key: K, value: V) W) Map[K, W]` |
| `Map[K, V]` | `map_keys[W: Hashable](transform: fn(key: K, value: V) W) Map[W, V]` |
| `Map[K, V]` | `fold[A](initial: A, step: fn(accumulator: A, key: K, value: V) A) A` |
| `Map[K, V]` | `fold_right[A]` uses the same step in reverse insertion order |
| `Map[K, V]` | `find(predicate: fn(key: K, value: V) Bool) Optional[MapEntry[K, V]]` |
| `Map[K, V]` | `find_last` uses the same predicate and entry result, searching from the end |
| `Map[K, V]` | `some(predicate: fn(key: K, value: V) Bool) Bool`; `every` uses the same predicate |
| `Map[K, V]` | `add(key: K, value: V) Map[K, V]`; `remove(key: K) Map[K, V]` |
| `Set[T]()` | Empty `Set[T]` |
| `Set[T](values)` | `Set[T]` of the distinct elements of the `List[T]` in first-seen order; `Set([1, 2])` infers `T` |
| `Set[T]` | `length() Int`; `contains(value: T) Bool` |
| `Set[T]` | `is_empty() Bool`; `filter(predicate: fn(value: T) Bool) Set[T]` |
| `Set[T]` | `map[U: Hashable](transform: fn(value: T) U) Set[U]` |
| `Set[T]` | `add(value: T) Set[T]`; `remove(value: T) Set[T]` |
| `Set[T]` | `fold[A](initial: A, step: fn(accumulator: A, value: T) A) A` |
| `Set[T]` | `fold_right[A]` uses the same step in reverse insertion order |
| `Set[T]` | `find(predicate: fn(value: T) Bool) Optional[T]` |
| `Set[T]` | `find_last` uses the same predicate and payload result, searching from the end |
| `Set[T]` | `some(predicate: fn(value: T) Bool) Bool`; `every` uses the same predicate |

An empty constructor needs explicit type arguments or a complete expected application, and creates fresh storage. `values[index]` equals `values.get(index)`: the element at an index, where negative indexes count from the end. An index out of range faults. Pass a default to avoid the fault: `values.get(0, default: 0)` needs no length check. Bytes and String `get` work the same way, and a String element is a one-scalar String. A size above the maximum `Int` faults.

`Map.add(key, value)` inserts or replaces and returns Unit. Replacing an equal map key keeps its original key and position; adding an existing set element changes nothing. Remove then add moves the entry to the end. Equality ignores insertion order. Use builders for construction with a sealed result.

Map `get`, `contains`, and `add` and Set `contains` and `add` are hash lookups (constant time on average). Map and Set `remove` keep order by shifting later entries, costing a fast copy proportional to size. List `contains` and `index_of` scan. A key mutated while stored becomes unreachable; remove it first or store a `.clone()` ([key consistency](equality-and-hashing.md#key-consistency)).

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

Enumeration returns owned results. Callbacks borrow the receiver for the traversal; they cannot mutate it.

Set `union`, `intersection`, `difference`, and `symmetric_difference` (values in exactly one operand) return new sets and leave both operands unchanged. `is_subset_of`, `is_superset_of`, and `is_disjoint_from` test the obvious relations; the empty set is a subset of, and disjoint from, every set.

```manuscript
import panic from "@std/core.ms"


fn positives(values: List[Int]) List[Int]:
    var result: List[Int] = []
    for value in values:
        if value > 0:
            result.append(value)
    return result

test "dynamic mutable data and explicit copies":
    if not (positives([3, -1, 2]) == [3, 2]):
        return panic("check failed")
    if [1].get(5, default: -1) != -1:
        return panic("check failed")
    var original = Map[String, Int]()
    original.add("a", 1)
    var updated = original.clone()
    updated.add("b", 2)
    updated.add("a", 3)
    if not (original.get("a") == some(1)):
        return panic("check failed")
    if not (updated.get("a") == some(3)):
        return panic("check failed")
```

Map `get_or` evaluates its fallback eagerly and never inserts. Map and Set `filter` return fresh storage in insertion order, copying retained values; predicates borrow the receiver. Set `map` also borrows its receiver and returns a fresh set whose output type must be `Hashable`; equal results keep the first payload and position. Callbacks run sequentially in the caller's context; faults and cancellation stop the traversal.

## Transforming Map keys and values

`map` transforms values and keeps keys; `map_keys` transforms keys (outputs must be `Hashable`) and keeps values. Callbacks receive `key` and `value`, borrow the receiver, and return an owned Map. Equal transformed keys keep the first key and position, and later entries replace the value, as in ordinary insertion. Optional and Result values are not flattened, and output values need not be `Hashable`.

```manuscript
fn increment_scores(scores: Map[String, Int]) Map[String, Int]:
    return scores.map(fn(name, score): score + 1)
```

## Reducing and querying

All of these borrow the receiver while callbacks run; mutating or clearing that receiver from a callback is rejected.

- `fold` goes in insertion order; the step takes the accumulator, then the key/value or element, and returns the next accumulator of type `A`. An empty receiver returns the initial value. `fold_right` goes in reverse.
- `find` stops at the first true predicate: a Set returns the element, a Map a fresh `MapEntry` (as in `entries()`; editing it does not update the Map). No match returns `none`. `find_last` searches from the end.
- `some` stops at the first true predicate and `every` at the first false one. Empty receivers give false and true without calling the predicate.

## Building data

The [collection reference](../../standard-library/reference/collections.md) lists all methods and constructors. Builders construct with a sealed result. See [generics and bounds](generics.md) and [equality and hashing](equality-and-hashing.md) for key eligibility.
