+++
title = "collections"
+++

# @std/collections.ms

`List` and `Map` are available in the prelude; no import required.

Other names require `import Name from "@std/collections.ms"`; explicit List/Map imports remain supported.

## CollectionError {data-api-kind="Alternative"}

Errors returned when a collection factory exceeds its supplied item limit.

```manuscript
type CollectionError:
    case InvalidInput
    case LimitExceeded
```

```manuscript
impl Error for CollectionError:
    fn message() -> String:
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
    fn set(index: Int, value: T) -> List[T]:
    fn remove(index: Int) -> List[T]:
    fn with_value(index: Int, value: T) -> List[T]:
    fn without(index: Int) -> List[T]:
    fn slice(start: Int, end: Int) -> List[T]:
    fn reverse_in_place() -> List[T]:
    fn reversed() -> List[T]:
    fn reverse() -> List[T]:
    fn sorted(compare: fn(left: T, right: T) -> Int) -> List[T]:
    fn filter(predicate: fn(value: T) -> Bool) -> List[T]:
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    fn some(predicate: fn(value: T) -> Bool) -> Bool:
    fn every(predicate: fn(value: T) -> Bool) -> Bool:
    fn for_each(operation: fn(value: T) -> Unit) -> Unit:
    fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]:
    fn map[U](transform: fn(value: T) -> U) -> List[U]:
    fn flat_map[U](transform: fn(value: T) -> List[U]) -> List[U]:
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn with_values(start: Int, delete_count: Int, replacement: List[T]) -> List[T]:
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
    fn get_or(key: T, fallback: U) -> U:
    fn fold[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
    fn find(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
    fn some(predicate: fn(key: T, value: U) -> Bool) -> Bool:
    fn every(predicate: fn(key: T, value: U) -> Bool) -> Bool:
    fn with_default(key: T, value: U) -> Map[T, U]:
    fn with_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]:
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
    fn with_entry(key: T, value: U) -> Map[T, U]:
    fn without(key: T) -> Map[T, U]:
```

## MapBuilder {data-api-kind="Native type"}

Adds entries efficiently before freezing them into a map.

```manuscript
type MapBuilder[T: Hashable, U]:
    fn freeze() -> Map[T, U]:
    fn with_entry(key: T, value: U) -> Unit:
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
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
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
    fn with_value(value: T) -> Set[T]:
    fn without(value: T) -> Set[T]:
```

## SetBuilder {data-api-kind="Native type"}

Adds unique values efficiently before freezing them into a set.

```manuscript
type SetBuilder[T: Hashable]:
    fn freeze() -> Set[T]:
    fn with_value(value: T) -> Unit:
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

