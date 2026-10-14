+++
title = "collections"
+++

# @std/collections.ms

`List`, `Map`, and `Set` are available in the prelude; no import required.

Other names require `import Name from "@std/collections.ms"`; explicit List/Map/Set imports remain supported.

## CollectionError {data-api-kind="Alternative"}

Errors returned when a collection factory exceeds its supplied item limit.

```manuscript
type CollectionError:
    case InvalidInput
    case LimitExceeded
    case OutOfRange
```

```manuscript
impl Error for CollectionError:
    fn message() -> String:
```

### CollectionError.InvalidInput

A count, item budget, or step is invalid: `count` or `max_items` is negative, or `range` has a zero `step`.

```manuscript
case InvalidInput
```

### CollectionError.LimitExceeded

The result would hold more items than `max_items`, or more than the runtime's ceiling of 268435456 (2^28) items when `max_items` is omitted.

```manuscript
case LimitExceeded
```

### CollectionError.OutOfRange

A slice bound lies outside 0 <= start <= end <= length() after negative bounds are resolved from the end.

```manuscript
case OutOfRange
```

### CollectionError.Error.message

Returns the fixed diagnostic `collection: <reason>`, such as `collection: limit exceeded`, without echoing values.

```manuscript
fn message() -> String:
```

## List {data-api-kind="Native type"}

An ordered mutable collection with indexing, iteration, and transformations.
Primitive backing stores Int and Float values at 64 bits, Bool values as bytes, and String references without an element box.
Generic forwarding retains the same List identity; clone and slice copy outer storage.

```manuscript
type List[T]:
    fn clone() -> List[T]:
    fn at(index: Int) -> Optional[T]:
    fn contains(value: T) -> Bool:
    fn index_of(value: T) -> Optional[Int]:
    fn last_index_of(value: T) -> Optional[Int]:
    fn first() -> Optional[T]:
    fn last() -> Optional[T]:
    fn is_empty() -> Bool:
    fn prepend(value: T) -> List[T]:
    fn insert(index: Int, value: T) -> List[T]:
    fn pop() -> Optional[T]:
    fn set(index: Int, value: T) -> List[T]:
    fn remove(index: Int) -> List[T]:
    fn slice(start: Int, end: Int) -> Result[List[T], CollectionError]:
    fn take(count: Int) -> List[T]:
    fn drop(count: Int) -> List[T]:
    fn reverse_in_place() -> List[T]:
    fn reversed() -> List[T]:
    fn sorted(compare: fn(left: T, right: T) -> Int) -> List[T]:
    fn filter(predicate: fn(value: T) -> Bool) -> List[T]:
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    fn count(predicate: fn(value: T) -> Bool) -> Int:
    fn distinct() -> List[T]:
    fn some(predicate: fn(value: T) -> Bool) -> Bool:
    fn every(predicate: fn(value: T) -> Bool) -> Bool:
    fn for_each(operation: fn(value: T) -> Unit) -> Unit:
    fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]:
    fn map[U](transform: fn(value: T) -> U) -> List[U]:
    fn flat_map[U](transform: fn(value: T) -> List[U]) -> List[U]:
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn splice(start: Int, delete_count: Int, replacement: List[T]) -> List[T]:
    fn fill(value: T, start: Int, end: Int) -> List[T]:
    fn copy_within(target: Int, start: Int, end: Int) -> List[T]:
    fn to_set() -> Set[T]:
    fn keys() -> List[Int]:
    fn entries() -> List[ListEntry[T]]:
    fn join(separator: String) -> String:
    fn append(value: T) -> List[T]:
    fn concat(other: List[T]) -> List[T]:
    fn length() -> Int:
```

### List.append

Adds `value` at the end in place and returns this same list.

```manuscript
fn append(value: T) -> List[T]:
```

### List.at

Returns an element; negative indexes are relative to the end, and out-of-range indexes return none.

```manuscript
fn at(index: Int) -> Optional[T]:
```

### List.clone

Returns a shallow copy with independent list storage.

```manuscript
fn clone() -> List[T]:
```

### List.concat

Returns a new list holding this list's elements followed by `other`; neither operand is changed.

```manuscript
fn concat(other: List[T]) -> List[T]:
```

### List.contains

Reports whether any element equals `value`, using the element type's Equal implementation; an empty list returns false.

```manuscript
fn contains(value: T) -> Bool:
```

### List.copy_within

Copies the elements in [start, end) to begin at index `target`, in place, and returns this list.
The list never grows: copying stops at the end of the list. Source bounds must satisfy 0 <= start <= end <= length() and a target must be within 0 through length(); otherwise the call faults.

```manuscript
fn copy_within(target: Int, start: Int, end: Int) -> List[T]:
```

### List.count

Counts values satisfying the predicate, calling it once per element in order.

```manuscript
fn count(predicate: fn(value: T) -> Bool) -> Int:
```

### List.distinct

Returns a new shallow List keeping each first equal element in order; elements require Equal.

```manuscript
fn distinct() -> List[T]:
```

### List.drop

Copies the remainder after min(count, length) into fresh shallow List storage.
Leaves the receiver unchanged; negative count is a programming fault.

```manuscript
fn drop(count: Int) -> List[T]:
```

### List.entries

Returns a new list of `ListEntry` records pairing each zero-based index with its element, in order.

```manuscript
fn entries() -> List[ListEntry[T]]:
```

### List.every

Returns true when every value satisfies the predicate; empty lists return true.

```manuscript
fn every(predicate: fn(value: T) -> Bool) -> Bool:
```

### List.fill

Sets elements in [start, end) to `value` in place and returns this list.
Bounds must satisfy 0 <= start <= end <= length(); negative or larger bounds fault rather than counting from the end, and an empty range changes nothing.

```manuscript
fn fill(value: T, start: Int, end: Int) -> List[T]:
```

### List.filter

Keeps matching values in their original order.

```manuscript
fn filter(predicate: fn(value: T) -> Bool) -> List[T]:
```

### List.find

Returns the first element for which `predicate` is true, or none; later elements are not tested after a match.

```manuscript
fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
```

### List.find_index

Returns the zero-based index of the first element for which `predicate` is true, or none.

```manuscript
fn find_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
```

### List.find_last

Searches from the end and returns the last element for which `predicate` is true, or none.

```manuscript
fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
```

### List.find_last_index

Searches from the end and returns the last matching zero-based index, or none.

```manuscript
fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
```

### List.first

Returns the first element, or none when the list is empty.

```manuscript
fn first() -> Optional[T]:
```

### List.flat_map[U]

Calls `transform` on each element in order and concatenates the returned lists into one new list; the receiver is unchanged.

```manuscript
fn flat_map[U](transform: fn(value: T) -> List[U]) -> List[U]:
```

### List.fold[A]

Reduces values from left to right, starting with `initial`.

```manuscript
fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
```

### List.fold_right[A]

Reduces values from right to left, starting with `initial`.

```manuscript
fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
```

### List.for_each

Calls operation(value:) over the initial backing slice and length; element writes can affect later calls, and append does not extend traversal.

```manuscript
fn for_each(operation: fn(value: T) -> Unit) -> Unit:
```

### List.group_by[K: Hashable]

Calls `key` once per element in order and returns a map from each distinct key to the elements that produced it.
Keys appear in first-seen order and each group keeps the original element order.

```manuscript
fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]:
```

### List.index_of

Returns the first equal element's zero-based index, or none; elements require Equal.

```manuscript
fn index_of(value: T) -> Optional[Int]:
```

### List.insert

Inserts value before index in place and returns this list; negative indexes count from the end.
Requires -length() <= index <= length(); index length() appends, and invalid indexes fault.

```manuscript
fn insert(index: Int, value: T) -> List[T]:
```

### List.is_empty

Reports whether the list has no elements.

```manuscript
fn is_empty() -> Bool:
```

### List.join

Concatenates the strings with `separator` between neighbors; an empty list returns an empty string.
Available only on List[String].

```manuscript
fn join(separator: String) -> String:
```

### List.keys

Returns a new list of the zero-based indexes 0 through length() - 1.

```manuscript
fn keys() -> List[Int]:
```

### List.last

Returns the last element, or none when the list is empty.

```manuscript
fn last() -> Optional[T]:
```

### List.last_index_of

Returns the last equal element's zero-based index, or none; elements require Equal.

```manuscript
fn last_index_of(value: T) -> Optional[Int]:
```

### List.length

Returns the number of elements.

```manuscript
fn length() -> Int:
```

### List.map[U]

Returns a new list holding `transform` applied to each element in order; the receiver is unchanged.

```manuscript
fn map[U](transform: fn(value: T) -> U) -> List[U]:
```

### List.pop

Removes and returns the last element in place, or none for an empty list.

```manuscript
fn pop() -> Optional[T]:
```

### List.prepend

Inserts `value` at index 0 in place, shifting existing elements one position later, and returns this same list.

```manuscript
fn prepend(value: T) -> List[T]:
```

### List.remove

Removes an element in place and returns this list; negative indexes count from the end.
Invalid indexes fault.
Shifts the suffix without clearing prior values retained in spare backing capacity.

```manuscript
fn remove(index: Int) -> List[T]:
```

### List.reverse_in_place

Reverses this list in place and returns the same instance.

```manuscript
fn reverse_in_place() -> List[T]:
```

### List.reversed

Returns a reversed shallow copy with independent outer storage; nested references remain shared.

```manuscript
fn reversed() -> List[T]:
```

### List.set

Replaces an element in place and returns this list; negative indexes count from the end.
Invalid indexes fault.

```manuscript
fn set(index: Int, value: T) -> List[T]:
```

### List.slice

Returns a new shallow List containing [start, end); outer storage is independent.
Negative bounds are relative to the end; bounds outside 0 <= start <= end <= length() return CollectionError.OutOfRange.

```manuscript
fn slice(start: Int, end: Int) -> Result[List[T], CollectionError]:
```

### List.some

Returns true when at least one value satisfies the predicate.

```manuscript
fn some(predicate: fn(value: T) -> Bool) -> Bool:
```

### List.sorted

Returns a new list sorted by negative/zero/positive comparator results.

```manuscript
fn sorted(compare: fn(left: T, right: T) -> Int) -> List[T]:
```

### List.splice

Replaces delete_count elements starting at start, mutating and returning this List.
Requires 0 <= start <= length and 0 <= delete_count <= length - start; invalid bounds fault without clamping.
Replacement references stay shallow; using this same List as replacement stages its prior values.
Shrinking retains prior values in spare backing capacity, following captured Go slice traversal.

```manuscript
fn splice(start: Int, delete_count: Int, replacement: List[T]) -> List[T]:
```

### List.take

Copies the first min(count, length) elements into fresh shallow List storage.
Leaves the receiver unchanged; negative count is a programming fault.

```manuscript
fn take(count: Int) -> List[T]:
```

### List.to_set

Returns a new set of the distinct elements, using Hashable equality; the first of equal elements is kept in insertion order.

```manuscript
fn to_set() -> Set[T]:
```

## ListBuilder {data-api-kind="Native type"}

Appends values efficiently before freezing them into a list.

```manuscript
type ListBuilder[T]:
    fn append(value: T) -> Unit:
    fn freeze() -> List[T]:
```

### ListBuilder.append

Adds `value` to the end of the shared builder and returns Unit.
A frozen builder faults.

```manuscript
fn append(value: T) -> Unit:
```

### ListBuilder.freeze

Seals the builder and returns the accumulated list without copying it.
Later `append` calls fault.

```manuscript
fn freeze() -> List[T]:
```

## ListEntry {data-api-kind="Record"}

One list index and its corresponding value.

```manuscript
type ListEntry[T]:
    index: Int
    value: T
```

### ListEntry.index

Zero-based position of the element in the list that produced this entry.

```manuscript
index: Int
```

### ListEntry.value

The element found at `index`.

```manuscript
value: T
```

## Map {data-api-kind="Native type"}

A mutable key-value collection. Keys use explicit `Hashable` value semantics.

```manuscript
type Map[T: Hashable, U]:
    fn clone() -> Map[T, U]:
    fn is_empty() -> Bool:
    fn filter(predicate: fn(key: T, value: U) -> Bool) -> Map[T, U]:
    fn map[W](transform: fn(key: T, value: U) -> W) -> Map[T, W]:
    fn map_keys[W: Hashable](transform: fn(key: T, value: U) -> W) -> Map[W, U]:
    fn get_or(key: T, fallback: U) -> U:
    fn fold[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
    fn fold_right[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
    fn find(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
    fn find_last(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
    fn some(predicate: fn(key: T, value: U) -> Bool) -> Bool:
    fn every(predicate: fn(key: T, value: U) -> Bool) -> Bool:
    fn add_default(key: T, value: U) -> Map[T, U]:
    fn add_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]:
    fn clear() -> Map[T, U]:
    fn keys() -> List[T]:
    fn values() -> List[U]:
    fn entries() -> List[MapEntry[T, U]]:
    fn merge(other: Map[T, U]) -> Map[T, U]:
    fn for_each(operation: fn(key: T, value: U) -> Unit) -> Unit:
    fn contains(key: T) -> Bool:
    fn get(key: T) -> Optional[U]:
    fn length() -> Int:
    fn add(key: T, value: U) -> Map[T, U]:
    fn remove(key: T) -> Map[T, U]:
```

### Map.add

Inserts or replaces a value and returns this map; replacement keeps the original key and insertion position.

```manuscript
fn add(key: T, value: U) -> Map[T, U]:
```

### Map.add_default

Inserts a default only when the key is absent and returns this map.
The supplied value evaluates normally even when the key already exists.

```manuscript
fn add_default(key: T, value: U) -> Map[T, U]:
```

### Map.add_default_from

Creates and inserts a default only when the key is absent, then returns this map.
Calls create(key:) once for absence; an existing key leaves its value and position unchanged.

```manuscript
fn add_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]:
```

### Map.clear

Removes every entry in place and returns this same map; aliases observe the empty map.

```manuscript
fn clear() -> Map[T, U]:
```

### Map.clone

Returns a shallow copy with independent map storage.

```manuscript
fn clone() -> Map[T, U]:
```

### Map.contains

Reports whether an equal key is present, using the key type's Hashable implementation.

```manuscript
fn contains(key: T) -> Bool:
```

### Map.entries

Returns a new list of fresh `MapEntry` records in insertion order; keys and values keep their original references.

```manuscript
fn entries() -> List[MapEntry[T, U]]:
```

### Map.every

Stops at the first nonmatching entry; empty maps return true.

```manuscript
fn every(predicate: fn(key: T, value: U) -> Bool) -> Bool:
```

### Map.filter

Copies matching entries in insertion order, retaining payload references.
Callbacks traverse a snapshot even when they mutate the receiver.

```manuscript
fn filter(predicate: fn(key: T, value: U) -> Bool) -> Map[T, U]:
```

### Map.find

Returns the first matching entry as a fresh record with shallow references.

```manuscript
fn find(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
```

### Map.find_last

Searches a snapshot from the end, stopping at the last matching entry.
Returns a fresh entry record retaining its original key/value references.

```manuscript
fn find_last(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
```

### Map.fold[A]

Reduces an entry snapshot in insertion order, starting with initial.

```manuscript
fn fold[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
```

### Map.fold_right[A]

Reduces an entry snapshot in reverse insertion order, starting with initial.

```manuscript
fn fold_right[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
```

### Map.for_each

Calls operation(key:, value:) sequentially over an insertion-order membership snapshot.

```manuscript
fn for_each(operation: fn(key: T, value: U) -> Unit) -> Unit:
```

### Map.get

Returns the value stored for an equal key, or none when the key is absent.

```manuscript
fn get(key: T) -> Optional[U]:
```

### Map.get_or

Returns the stored value or an eagerly evaluated fallback without inserting.

```manuscript
fn get_or(key: T, fallback: U) -> U:
```

### Map.is_empty

Reports whether this map has no entries.

```manuscript
fn is_empty() -> Bool:
```

### Map.keys

Returns a new list of the keys in insertion order.

```manuscript
fn keys() -> List[T]:
```

### Map.length

Returns the number of entries.

```manuscript
fn length() -> Int:
```

### Map.map[W]

Transforms values in snapshot insertion order, retaining original keys.
Returns independent outer storage with shallow key and result references.

```manuscript
fn map[W](transform: fn(key: T, value: U) -> W) -> Map[T, W]:
```

### Map.map_keys[W: Hashable]

Transforms keys in snapshot insertion order, retaining value references.
Equal outputs keep the first key/position and the last input value.

```manuscript
fn map_keys[W: Hashable](transform: fn(key: T, value: U) -> W) -> Map[W, U]:
```

### Map.merge

Copies every entry of `other` into this map in place and returns this map.
Existing keys keep their position and key but take the value from `other`; new keys append in `other` order. `other` is unchanged.

```manuscript
fn merge(other: Map[T, U]) -> Map[T, U]:
```

### Map.remove

Removes an equal key and returns this same Map; remaining entries retain insertion order.
An absent key leaves values and ordering unchanged; lookup uses the selected Equal/Hashable scope.

```manuscript
fn remove(key: T) -> Map[T, U]:
```

### Map.some

Stops at the first matching entry; empty maps return false.

```manuscript
fn some(predicate: fn(key: T, value: U) -> Bool) -> Bool:
```

### Map.values

Returns a new list of the values in insertion order.

```manuscript
fn values() -> List[U]:
```

## MapBuilder {data-api-kind="Native type"}

Adds entries efficiently before freezing them into a map.

```manuscript
type MapBuilder[T: Hashable, U]:
    fn freeze() -> Map[T, U]:
    fn add(key: T, value: U) -> Unit:
```

### MapBuilder.add

Inserts or replaces an entry in the shared builder; returns Unit like all builder mutations.
Replacement retains the original key and insertion position; a sealed builder faults.

```manuscript
fn add(key: T, value: U) -> Unit:
```

### MapBuilder.freeze

Seals the builder and returns the accumulated map without copying it.
Later `add` calls fault.

```manuscript
fn freeze() -> Map[T, U]:
```

## MapEntry {data-api-kind="Record"}

One key-value pair returned by `Map.entries`.

```manuscript
type MapEntry[T: Hashable, U]:
    key: T
    value: U
```

### MapEntry.key

The lookup identity of the pair; unique within its map under Hashable equality.

```manuscript
key: T
```

### MapEntry.value

The payload stored for `key`; the reference is shared with the map, not copied.

```manuscript
value: U
```

## Set {data-api-kind="Native type"}

A mutable collection of unique values using explicit `Hashable` value semantics.

```manuscript
type Set[T: Hashable]:
    fn clone() -> Set[T]:
    fn is_empty() -> Bool:
    fn filter(predicate: fn(value: T) -> Bool) -> Set[T]:
    fn map[U: Hashable](transform: fn(value: T) -> U) -> Set[U]:
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn some(predicate: fn(value: T) -> Bool) -> Bool:
    fn every(predicate: fn(value: T) -> Bool) -> Bool:
    fn union(other: Set[T]) -> Set[T]:
    fn intersection(other: Set[T]) -> Set[T]:
    fn difference(other: Set[T]) -> Set[T]:
    fn symmetric_difference(other: Set[T]) -> Set[T]:
    fn is_subset_of(other: Set[T]) -> Bool:
    fn is_superset_of(other: Set[T]) -> Bool:
    fn is_disjoint_from(other: Set[T]) -> Bool:
    fn clear() -> Set[T]:
    fn values() -> List[T]:
    fn entries() -> List[List[T]]:
    fn for_each(operation: fn(value: T) -> Unit) -> Unit:
    fn contains(value: T) -> Bool:
    fn length() -> Int:
    fn add(value: T) -> Set[T]:
    fn remove(value: T) -> Set[T]:
```

### Set.add

Adds a value in place and returns this set; an equal value retains its original payload and position.

```manuscript
fn add(value: T) -> Set[T]:
```

### Set.clear

Removes all values in place and returns this set; aliases observe the empty set.

```manuscript
fn clear() -> Set[T]:
```

### Set.clone

Copies outer storage, retaining element references and insertion order.

```manuscript
fn clone() -> Set[T]:
```

### Set.contains

Reports whether an equal value is present, using the element's Hashable implementation.

```manuscript
fn contains(value: T) -> Bool:
```

### Set.difference

Returns a new set of receiver values absent from right, preserving receiver insertion order.

```manuscript
fn difference(other: Set[T]) -> Set[T]:
```

### Set.entries

Returns a new list of [value, value] lists in insertion order.

```manuscript
fn entries() -> List[List[T]]:
```

### Set.every

Stops at the first nonmatching element; empty sets return true.

```manuscript
fn every(predicate: fn(value: T) -> Bool) -> Bool:
```

### Set.filter

Copies matching elements in insertion order, retaining payload references.
Callbacks traverse a snapshot even when they mutate the receiver.

```manuscript
fn filter(predicate: fn(value: T) -> Bool) -> Set[T]:
```

### Set.find

Returns the original first matching element, or none.

```manuscript
fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
```

### Set.find_last

Searches a snapshot from the end, returning the original last matching element.

```manuscript
fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
```

### Set.fold[A]

Reduces an element snapshot in insertion order, starting with initial.

```manuscript
fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
```

### Set.fold_right[A]

Reduces an element snapshot in reverse insertion order, starting with initial.

```manuscript
fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
```

### Set.for_each

Calls operation(value:) sequentially over an insertion-order membership snapshot.

```manuscript
fn for_each(operation: fn(value: T) -> Unit) -> Unit:
```

### Set.intersection

Returns a new set of receiver values also in right, preserving receiver insertion order.

```manuscript
fn intersection(other: Set[T]) -> Set[T]:
```

### Set.is_disjoint_from

Tests whether the operands have no common values.

```manuscript
fn is_disjoint_from(other: Set[T]) -> Bool:
```

### Set.is_empty

Reports whether this set has no elements.

```manuscript
fn is_empty() -> Bool:
```

### Set.is_subset_of

Tests whether every receiver value also occurs in right.

```manuscript
fn is_subset_of(other: Set[T]) -> Bool:
```

### Set.is_superset_of

Tests whether every right value also occurs in the receiver.

```manuscript
fn is_superset_of(other: Set[T]) -> Bool:
```

### Set.length

Returns the number of distinct values currently stored.

```manuscript
fn length() -> Int:
```

### Set.map[U: Hashable]

Transforms a snapshot into a fresh set, retaining the first equal result.

```manuscript
fn map[U: Hashable](transform: fn(value: T) -> U) -> Set[U]:
```

### Set.remove

Removes an equal value in place and returns this set; an absent value leaves it unchanged.

```manuscript
fn remove(value: T) -> Set[T]:
```

### Set.some

Stops at the first matching element; empty sets return false.

```manuscript
fn some(predicate: fn(value: T) -> Bool) -> Bool:
```

### Set.symmetric_difference

Returns a new set of values in exactly one operand; leaves both operands unchanged.

```manuscript
fn symmetric_difference(other: Set[T]) -> Set[T]:
```

### Set.union

Returns a new set with receiver values followed by right-only values in insertion order.

```manuscript
fn union(other: Set[T]) -> Set[T]:
```

### Set.values

Returns a shallow list of values in insertion order.

```manuscript
fn values() -> List[T]:
```

## SetBuilder {data-api-kind="Native type"}

Adds unique values efficiently before freezing them into a set.

```manuscript
type SetBuilder[T: Hashable]:
    fn freeze() -> Set[T]:
    fn add(value: T) -> Unit:
```

### SetBuilder.add

Adds a value to the shared builder; returns Unit like all builder mutations.
Equal values retain the first payload and position; a sealed builder faults.

```manuscript
fn add(value: T) -> Unit:
```

### SetBuilder.freeze

Seals the builder and returns the accumulated set without copying it.
Later `add` calls fault.

```manuscript
fn freeze() -> Set[T]:
```

## filled {data-api-kind="Function"}

Creates a list containing `value` repeated `count` times.

```manuscript
fn filled[T](value: T, count: Int, max_items: Optional[Int] = none) -> Result[List[T], CollectionError]:
```

## map_from_entries {data-api-kind="Function"}

Builds a map from entries. Later entries replace earlier values for duplicate keys.

```manuscript
fn map_from_entries[K: Hashable, V](entries: List[MapEntry[K, V]]) -> Map[K, V]:
```

## range {data-api-kind="Function"}

Creates integers from `start` up to but excluding `end` using `step`.

```manuscript
fn range(start: Int, end: Int, step: Int, max_items: Optional[Int] = none) -> Result[List[Int], CollectionError]:
```

