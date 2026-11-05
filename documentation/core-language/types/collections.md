+++
title = "Collections"
weight = 3
+++

# Collections

Choose a `List` for an ordered sequence, a `Map` for lookup by key, and a `Set` to keep distinct values. Declare a collection with `var` when you will update it; use `.clone()` when you need an independent copy. See [mutation and references](references.md) for moves and borrows.

`List`, `Map`, `Set`, `ListEntry[T]`, and `MapEntry[K: Hashable, V]` are prelude names (with `Optional`, `Result`, `Error`, `Equal`, `Hashable`); importing them is rejected. Builders and factories need imports. See [names and declaration order](../modules/declarations.md#names-and-declaration-order).

| Type | Contents |
| --- | --- |
| `List[T]` | Elements of type `T` |
| `Map[K, V]` | Keys of type `K` and values of type `V` |
| `Set[T]` | Distinct elements of type `T` |

## List literals

Brackets construct mutable lists of values:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"[1, 2, 3]\n0\n0\n0\n"} -->
```manuscript
export fn main() Int:
    let values = [1, 2, 3]
    let empty: List[Int] = []
    let also_empty = List[Int]()
    let sized = List[Int](reserve: 1000)
    print(values)
    print(empty.length())
    print(also_empty.length())
    print(sized.length())
    return 0
```

```text
[1, 2, 3]
0
0
0
```

`reserve: n` preallocates room for `n` items so appending up to that count does not regrow the list. The list stays empty; a negative or `none` reserve preallocates nothing.

The first literal infers `List[Int]`; an empty literal needs an annotation or expected type. Every element must match the element type (no implicit numeric conversion) and evaluates left to right. See [collections as arguments](../functions/declarations-and-calls.md#collections-as-arguments).

## Map literals

Braces construct mutable maps:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"3\n0\n"} -->
```manuscript
export fn main() Int:
    let scores = {"Ada": 3, "Lin": 5}
    let empty: Map[String, Int] = {}
    print(scores.get_or("Ada", 0))
    print(empty.length())
    return 0
```

```text
3
0
```

Entries are `key: value`, trailing commas allowed. Keys are expressions: `{name: score}` uses the value of `name`; `{"name": score}` uses a String. Map literals never construct records.

- A nonempty literal infers key and value types independently; an expected Map type propagates to both. An empty map needs an annotation or expected type.
- Keys must be `Hashable`.
- Entries evaluate once, in written order, key before value.
- Duplicate keys keep their first position and last value, like `add`.

## Element requirements

Lists and map values accept functions, interface values, builders and resources. Moving a resource into a collection transfers its cleanup duty to that collection; [aggregate cleanup](../cleanup/closeable.md#records-and-collections-close-what-they-hold) closes owned resources at scope end. Map keys and set elements also require `Hashable`.

Applications are invariant: `List[Int]` is not a `List[Float]`, and no implicit unions or numeric conversions apply.

This complete negative example is intentionally rejected. Save it as `example.ms` and run `ms check example.ms`:

<!-- manuscript-example: {"mode":"reject","stderr_contains":["expected Int, found Float","cannot infer list element type"]} -->
```manuscript
export fn main() Int:
    let nested: List[List[Int]] = [[], [1, 2]]
    // Rejected: incompatible Int and Float elements.
    let mixed = [1, 2.0]
    // Rejected: no element type can be inferred.
    let unknown = []
    return 0
```

The diagnostic includes `expected Int, found Float`, `cannot infer list element type`.

An expected type propagates into inner literals. Without one, elements must agree on one type; `none` needs another element or context to fix its payload, so write `let values: List[Int?] = [none, 1]`. Neither `[none, 1]` nor `[none]` supplies the required optional context on its own. Collections can hold [recursive data](records.md#recursive-data) but derive no hashing.

## Iteration

Maps and sets iterate in insertion order, with a [for loop](../control-flow/loops.md).

### Walking two lists, or a list with its index

`xs.entries()` pairs each element with its index, and `a.zip(b)` pairs two lists by position. Neither needs a nested index loop:

Save as `pairs.ms` and run `ms run pairs.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"ann: 90\nbo: 72\n2\n2\n1\n","filename":"pairs.ms"} -->
```manuscript
export fn main() Int:
    let names = ["ann", "bo", "cy"]
    let scores = [90, 72]
    for pair in names.zip(scores):
        print("{pair.first}: {pair.second}")
    for part in [1, 2, 3, 4, 5].chunks(2):
        print(part.length())
    return 0
```

```text
ann: 90
bo: 72
2
2
1
```

## Mutation and copies

Mutators update the receiver in place and return Unit; a `let` binding cannot be mutated, so declare the collection with `var`.

- List: `append`, `prepend`, `insert`, `set`, `replace`, `swap`, `remove`, `splice`, `fill`, `copy_within`, `reverse`.
- Map: `add`, `remove`, `add_default`, `add_default_from`, `merge`, `clear`. Removing an absent key is a no-op.
- Set: `add`, `remove`, `clear`.

List details:

- `set(index:, value:)` and `remove(index:)` accept negative indexes and fault on invalid ones.
- `replace(index:, value:)` stores `value` and returns the element that was there; `swap(i:, j:)` exchanges two elements. Both move elements without copying them, so they take an element out of a list of owned values (`items.replace(0, none)` on a `List[T?]`) and reorder it without `.clone()`. Both accept negative indexes and fault on invalid ones.
- `insert(index:, value:)` places before `index`, valid from `-length()` to `length()` (which appends).
- `pop()` returns the last element as the value, or `none` when empty.
- `splice(start:, delete_count:, replacement:)` needs `0 <= start <= length()` and `delete_count <= length() - start`.
- Invalid bounds fault; nothing is clamped.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"[1, 2, 3]\n[1, 2]\n"} -->
```manuscript
export fn main() Int:
    var values = [1, 2]
    let copy = values.clone()
    values.append(3)
    // values now contains [1, 2, 3]; copy still contains [1, 2].
    print(values)
    print(copy)
    return 0
```

```text
[1, 2, 3]
[1, 2]
```

Clones copy nested values too. `map`, `filter`, `slice`, `concat`, `sorted`, `reversed`, and set algebra return independent owned results (Bytes `reversed()` too).

List `slice` returns `Result[List[T], Error]` with strict bounds `0 <= start <= end <= length()` after resolving negative bounds from the end; otherwise an `Error` of kind `"ERANGE"`. See the [half-open slice rules](../basics/text-and-bytes.md#half-open-slices).

A collection loop or non-escaping callback borrows the receiver for the traversal. The checker rejects mutation, reassignment, or a move of that receiver while the borrow is live. To mutate the original while traversing independent data, make an explicit `.clone()` first.

### Choosing a copy or an update {#naming-and-migration}

Mutating methods such as `append`, `set`, `add` and `reverse` update a `var` receiver. Transforms such as `concat`, `filter`, `sorted` and `reversed` return independent results. For bytes, `slice` copies and `view(start, end)` borrows a range; see [half-open slices](../basics/text-and-bytes.md#half-open-slices).

Use `Queue` from `@std/collections/queue.ms` for first-in, first-out work (`enqueue`, `dequeue`, `peek`); `dequeue` is O(1). Use `Deque` when adding or removing at both ends. Both are owned values: declare them with `var` to mutate and use `.clone()` for an independent copy.

Map `add_default` evaluates its argument and inserts only when absent; `add_default_from` calls `create(key:)` once, only when absent. Neither replaces an existing value or position. For an independent map, bind `var copy = map.clone()` and call `copy.add_default(...)`.

Builder mutations return Unit; `build` returns the sealed result. `StringBuilder` and `BytesBuilder` are owned values like `List`: declare them with `var`, pass them with `var`, and `build` takes ownership of them, so using one after `build` is a move error. `drain` returns the content so far and leaves the builder empty, for a builder held in a record field, where `build` cannot move it out.

## Other collections

The standard library adds collections written in Manuscript. Each follows value ownership: use `.clone()` for an independent deep copy. Find exact signatures with `ms search_symbol <name>`.

| Type | Use it for |
| --- | --- |
| `Queue[T]` (`@std/collections/queue.ms`, owned) | First-in, first-out work, optionally bounded; `PriorityQueue[T]` dequeues in `Comparable` order, smallest first, with FIFO ties |
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
| `List[T](reserve: Int?)` | Empty `List[T]` with room for `reserve` items |
| `List[T]` | `length() Int`; `get(index: Int, default: T?) T`; `[index] T` |
| `List[T]` | `append(value: T) Unit`; `concat(values: List[T]) List[T]` |
| `List[T]` | `set(index: Int, value: T) Unit` (also `xs[index] = value`); `remove(index: Int) Unit` |
| `List[T]` | `insert(index: Int, value: T) Unit`; `pop() T?` |
| `Map[K, V]()` | Empty `Map[K, V]` |
| `Map[K, V]` | `length() Int`; `get(key: K) V?`; `contains(key: K) Bool`; `[key] V` faults with `map key not found: <key>` when absent |
| `Map[K, V]` | `is_empty() Bool`; `get_or(key: K, fallback: V) V` |
| `Map[K, V]` | `filter(predicate: fn(K, V) Bool) Map[K, V]` |
| `Map[K, V]` | `map[W](transform: fn(K, V) W) Map[K, W]` |
| `Map[K, V]` | `map_keys[W: Hashable](transform: fn(K, V) W) Map[W, V]` |
| `Map[K, V]` | `fold[A](initial: A, step: fn(A, K, V) A) A` |
| `Map[K, V]` | `fold_right[A]` uses the same step in reverse insertion order |
| `Map[K, V]` | `find(predicate: fn(K, V) Bool) MapEntry[K, V]?` |
| `Map[K, V]` | `find_last` uses the same predicate and entry result, searching from the end |
| `Map[K, V]` | `any(predicate: fn(K, V) Bool) Bool`; `all` uses the same predicate |
| `Map[K, V]` | `add(key: K, value: V) Unit`; `remove(key: K) Unit`; `m[key] = value` is `m.add(key, value)` and needs `var m` |
| `Map[K, V]` | `update(key: K, initial: V, change: fn(V) V) Unit` stores `change` applied to the stored value, or to `initial` when absent (`counts.update(word, 0, fn n: n + 1)`); needs `var m` and a cloneable key |
| `Set[T]()` | Empty `Set[T]` |
| `Set[T](values)` | `Set[T]` of the distinct elements of the `List[T]` in first-seen order; `Set([1, 2])` infers `T` |
| `Set[T]` | `length() Int`; `contains(value: T) Bool` |
| `Set[T]` | `is_empty() Bool`; `filter(predicate: fn(T) Bool) Set[T]` |
| `Set[T]` | `map[U: Hashable](transform: fn(T) U) Set[U]` |
| `Set[T]` | `add(value: T) Unit`; `remove(value: T) Unit` |
| `Set[T]` | `fold[A](initial: A, step: fn(A, T) A) A` |
| `Set[T]` | `fold_right[A]` uses the same step in reverse insertion order |
| `Set[T]` | `find(predicate: fn(T) Bool) T?` |
| `Set[T]` | `find_last` uses the same predicate and payload result, searching from the end |
| `Set[T]` | `any(predicate: fn(T) Bool) Bool`; `all` uses the same predicate |

An empty constructor needs explicit type arguments or a complete expected application, and creates fresh storage. `values[index]` equals `values.get(index)`: the element at an index, where negative indexes count from the end. An index out of range faults. Pass a default to avoid the fault: `values.get(0, default: 0)` needs no length check. Bytes and String `get` work the same way, and a String element is a one-scalar String. A size above the maximum `Int` faults.

`Map.add(key, value)` inserts or replaces and returns Unit. Replacing an equal map key keeps its original key and position; adding an existing set element changes nothing. Remove then add moves the entry to the end. Equality ignores insertion order. Use builders for construction with a sealed result.

Map `get`, `contains`, and `add` and Set `contains` and `add` are hash lookups (constant time on average). Map and Set `remove` keep order by shifting later entries, costing a fast copy proportional to size. List `contains` and `index_of` scan. A key mutated while stored becomes unreachable; remove it first or store a `.clone()` ([key consistency](equality-and-hashing.md#key-consistency)).

### Search and enumeration

| Operation | Result |
| --- | --- |
| List `index_of(value:)`, `last_index_of(value:)` | First or last equal element's zero-based index, or `none`; these searches require `Equal` elements. |
| List `find_index(predicate:)`, `find_last_index(predicate:)` | First or last matching index, or `none`. `find` and `find_last` return the matching value instead. |
| List `count(predicate:)` | Number of elements whose predicate returns true, calling it once per element in order. |
| List `any(predicate:)`, `all(predicate:)` | Whether some or every element satisfies the predicate; stops at the first deciding element. Empty lists give `false` and `true`. |
| List `max_by(key:)`, `min_by(key:)` | The first element whose key (a `Comparable` value from `key(element)`) is greatest or least, or `none` when empty. Calls `key` once per element in order; ties keep the earlier element. Like `find`, the result is a copy of the element. |
| List `distinct()` | A new list keeping the first of each group of equal elements in original order; requires `Equal` elements. |
| List `keys()`, `entries()` | A new list of indexes, or `List[ListEntry[T]]` records containing `index` and `value`. |
| List `zip(other)` | A new list of `Pair[T, U]` records (`first` from the receiver, `second` from `other`), as long as the shorter list. |
| List `chunks(size)`, `windows(size)` | Lists of copies of `size` consecutive elements: `chunks` splits (the last may be shorter), `windows` overlaps (a list shorter than `size` gives none). A `size` of zero or less is a fault. |
| List `partition(predicate)` | A `Partition[T]` record whose `matching` and `rest` lists keep the original order; the predicate runs once per element. |
| Map `keys()`, `values()`, `entries()` | New lists in insertion order; entries are `MapEntry[K, V]` records with `key` and `value`. |
| Set `values()` | A new list in insertion order. |
| List/Set `for_each(operation:)` | Calls `operation(value:)` sequentially for each value; returns Unit. |
| Map `for_each(operation:)` | Calls `operation(key:, value:)` sequentially for each entry; returns Unit. |

Enumeration returns owned results. Callbacks borrow the receiver for the traversal; they cannot mutate it.

List `sorted()` returns a new list in ascending natural order and `sort()` orders the list in place; both are stable. Without a `compare:` function the element type must be `Comparable` (Int, Float, String, the sized numerics, or a type with `impl Comparable`), and Float orders NaN above every other value. Pass `compare: fn a, b: ...` to order by anything else; a negative result puts the first argument first. `sum()` adds Int, Float, or sized numeric elements with `+` (Int overflow faults; an empty list sums to zero). `min()` and `max()` return a copy of the least or greatest element of a `Comparable` list, the first of equal elements, or `none` for an empty list.

Save this test as `example.ms` and run `ms test example.ms`:

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::sorting and aggregates\nPASS example.ms::sorting and aggregates\n1 tests, 0 failed\n"} -->
```manuscript
import panic from "@std/core.ms"

test "sorting and aggregates":
    var scores = [3, 1, 2]
    if scores.sorted() != [1, 2, 3]:
        return panic("check failed")
    scores.sort(fn a, b: b - a)
    if scores != [3, 2, 1]:
        return panic("check failed")
    if scores.sum() != 6 or scores.max() != 3 or not List[Int]().min().is_none():
        return panic("check failed")
```

```text
RUN example.ms::sorting and aggregates
PASS example.ms::sorting and aggregates
1 tests, 0 failed
```

Set `union`, `intersection`, `difference`, and `symmetric_difference` (values in exactly one operand) return new sets and leave both operands unchanged. `is_subset_of`, `is_superset_of`, and `is_disjoint_from` test the obvious relations; the empty set is a subset of, and disjoint from, every set.

Save this complete test as `example.ms` and run `ms test example.ms`:

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::dynamic mutable data and explicit copies\nPASS example.ms::dynamic mutable data and explicit copies\n1 tests, 0 failed\n"} -->
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
    if not (original.get("a") == 1):
        return panic("check failed")
    if not (updated.get("a") == 3):
        return panic("check failed")
```

```text
RUN example.ms::dynamic mutable data and explicit copies
PASS example.ms::dynamic mutable data and explicit copies
1 tests, 0 failed
```

Map `get_or` evaluates its fallback eagerly and never inserts. Map and Set `filter` return fresh storage in insertion order, copying retained values; predicates borrow the receiver. Set `map` also borrows its receiver and returns a fresh set whose output type must be `Hashable`; equal results keep the first payload and position. Callbacks run sequentially in the caller's context; faults and cancellation stop the traversal.

## Transforming Map keys and values

`map` transforms values and keeps keys; `map_keys` transforms keys (outputs must be `Hashable`) and keeps values. Callbacks receive `key` and `value`, borrow the receiver, and return an owned Map. Equal transformed keys keep the first key and position, and later entries replace the value, as in ordinary insertion. Optional and Result values are not flattened, and output values need not be `Hashable`.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"4\n"} -->
```manuscript
fn increment_scores(scores: Map[String, Int]) Map[String, Int]:
    return scores.map(fn name, score: score + 1)

export fn main() Int:
    print(increment_scores({"Ada": 3}).get_or("Ada", 0))
    return 0
```

```text
4
```

## Reducing and querying

All of these borrow the receiver while callbacks run; mutating or clearing that receiver from a callback is rejected.

- `fold` goes in insertion order; the step takes the accumulator, then the key/value or element, and returns the next accumulator of type `A`. An empty receiver returns the initial value. `fold_right` goes in reverse.
- `find` stops at the first true predicate: a Set returns the element, a Map a fresh `MapEntry` (as in `entries()`; editing it does not update the Map). No match returns `none`. `find_last` searches from the end.
- `any` stops at the first true predicate and `all` at the first false one. Empty receivers give false and true without calling the predicate.

## Building data

The [collection reference](../../standard-library/reference/collections/collections.ms.md) lists all methods and constructors. Builders construct with a sealed result. See [generics and bounds](generics.md) and [equality and hashing](equality-and-hashing.md) for key eligibility.
