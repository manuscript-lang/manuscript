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

### CollectionError.OutOfRange

A slice bound lies outside 0 <= start <= end <= length() after negative bounds are resolved from the end.

```manuscript
case OutOfRange
```

## List {data-api-kind="Native type"}

An ordered collection of values with indexing, iteration, and transformation operations.

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
    fn concat(values: List[T]) -> List[T]:
    fn length() -> Int:
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

### List.every

Returns true when every value satisfies the predicate; empty lists return true.

```manuscript
fn every(predicate: fn(value: T) -> Bool) -> Bool:
```

### List.filter

Keeps matching values in their original order.

```manuscript
fn filter(predicate: fn(value: T) -> Bool) -> List[T]:
```

### List.find_last_index

Searches from the end and returns the last matching zero-based index, or none.

```manuscript
fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
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

### List.last_index_of

Returns the last equal element's zero-based index, or none; elements require Equal.

```manuscript
fn last_index_of(value: T) -> Optional[Int]:
```

### List.pop

Removes and returns the last element in place, or none for an empty list.

```manuscript
fn pop() -> Optional[T]:
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

## ListBuilder {data-api-kind="Native type"}

Appends values efficiently before freezing them into a list.

```manuscript
type ListBuilder[T]:
    fn append(value: T) -> Unit:
    fn freeze() -> List[T]:
```

## ListEntry {data-api-kind="Record"}

One list index and its corresponding value.

```manuscript
type ListEntry[T]:
    index: Int
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

### Map.clone

Returns a shallow copy with independent map storage.

```manuscript
fn clone() -> Map[T, U]:
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

## MapEntry {data-api-kind="Record"}

One key-value pair returned by `Map.entries`.

```manuscript
type MapEntry[T: Hashable, U]:
    key: T
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
    fn union(right: Set[T]) -> Set[T]:
    fn intersection(right: Set[T]) -> Set[T]:
    fn difference(right: Set[T]) -> Set[T]:
    fn symmetric_difference(right: Set[T]) -> Set[T]:
    fn is_subset_of(right: Set[T]) -> Bool:
    fn is_superset_of(right: Set[T]) -> Bool:
    fn is_disjoint_from(right: Set[T]) -> Bool:
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
fn difference(right: Set[T]) -> Set[T]:
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
fn intersection(right: Set[T]) -> Set[T]:
```

### Set.is_disjoint_from

Tests whether the operands have no common values.

```manuscript
fn is_disjoint_from(right: Set[T]) -> Bool:
```

### Set.is_empty

Reports whether this set has no elements.

```manuscript
fn is_empty() -> Bool:
```

### Set.is_subset_of

Tests whether every receiver value also occurs in right.

```manuscript
fn is_subset_of(right: Set[T]) -> Bool:
```

### Set.is_superset_of

Tests whether every right value also occurs in the receiver.

```manuscript
fn is_superset_of(right: Set[T]) -> Bool:
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
fn symmetric_difference(right: Set[T]) -> Set[T]:
```

### Set.union

Returns a new set with receiver values followed by right-only values in insertion order.

```manuscript
fn union(right: Set[T]) -> Set[T]:
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

