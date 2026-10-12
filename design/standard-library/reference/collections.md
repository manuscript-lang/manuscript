+++
title = "collections"
+++

# @std/collections.ms

Import each required symbol with `import Name from "@std/collections.ms"`.

## List {data-api-kind="Native type"}

```manuscript
type List[T]:
    fn at(index: Int) -> Optional[T]
    fn contains(value: T) -> Bool
    fn index_of(value: T) -> Optional[Int]
    fn last_index_of(value: T) -> Optional[Int]
    fn first() -> Optional[T]
    fn last() -> Optional[T]
    fn is_empty() -> Bool
    fn prepend(value: T) -> List[T]
    fn with_value(index: Int, value: T) -> List[T]
    fn without(index: Int) -> List[T]
    fn slice(start: Int, end: Int) -> List[T]
    fn reverse() -> List[T]
    fn sorted(compare: fn(left: T, right: T) -> Int) -> List[T]
    fn filter(predicate: fn(value: T) -> Bool) -> List[T]
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]
    fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]
    fn find_index(predicate: fn(value: T) -> Bool) -> Optional[Int]
    fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]
    fn some(predicate: fn(value: T) -> Bool) -> Bool
    fn every(predicate: fn(value: T) -> Bool) -> Bool
    fn for_each(operation: fn(value: T) -> Unit) -> Unit
    fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]
    fn map[U](transform: fn(value: T) -> U) -> List[U]
    fn flat_map[U](transform: fn(value: T) -> List[U]) -> List[U]
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A
    fn with_values(start: Int, delete_count: Int, replacement: List[T]) -> List[T]
    fn fill(value: T, start: Int, end: Int) -> List[T]
    fn copy_within(target: Int, start: Int, end: Int) -> List[T]
    fn to_set() -> Set[T]
    fn keys() -> List[Int]
    fn entries() -> List[ListEntry[T]]
    fn join(separator: String) -> String
    fn append(value: T) -> List[T]
    fn concat(values: List[T]) -> List[T]
    fn get(index: Int) -> Optional[T]
    fn length() -> Int
```

## ListEntry {data-api-kind="Record"}

```manuscript
type ListEntry[T]:
    index: Int
    value: T
```

## Map {data-api-kind="Native type"}

```manuscript
type Map[T: Hashable, U]:
    fn with_default(key: T, value: U) -> Map[T, U]
    fn with_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]
    fn clear() -> Map[T, U]
    fn keys() -> List[T]
    fn values() -> List[U]
    fn entries() -> List[MapEntry[T, U]]
    fn merge(other: Map[T, U]) -> Map[T, U]
    fn for_each(operation: fn(key: T, value: U) -> Unit) -> Unit
    fn contains(key: T) -> Bool
    fn get(key: T) -> Optional[U]
    fn length() -> Int
    fn with_entry(key: T, value: U) -> Map[T, U]
    fn without(key: T) -> Map[T, U]
```

## MapEntry {data-api-kind="Record"}

```manuscript
type MapEntry[T: Hashable, U]:
    key: T
    value: U
```

## Set {data-api-kind="Native type"}

```manuscript
type Set[T: Hashable]:
    fn union(right: Set[T]) -> Set[T]
    fn intersection(right: Set[T]) -> Set[T]
    fn difference(right: Set[T]) -> Set[T]
    fn symmetric_difference(right: Set[T]) -> Set[T]
    fn is_subset_of(right: Set[T]) -> Bool
    fn is_superset_of(right: Set[T]) -> Bool
    fn is_disjoint_from(right: Set[T]) -> Bool
    fn clear() -> Set[T]
    fn values() -> List[T]
    fn entries() -> List[List[T]]
    fn for_each(operation: fn(value: T) -> Unit) -> Unit
    fn contains(value: T) -> Bool
    fn length() -> Int
    fn with_value(value: T) -> Set[T]
    fn without(value: T) -> Set[T]
```

## at {data-api-kind="Function"}

```manuscript
fn at[T](values: List[T], index: Int) -> Optional[T]
```

## contains {data-api-kind="Function"}

```manuscript
fn contains[T: Equal](values: List[T], value: T) -> Bool
```

## copy_within {data-api-kind="Function"}

```manuscript
fn copy_within[T](values: List[T], target: Int, start: Int, end: Int) -> List[T]
```

## difference {data-api-kind="Function"}

```manuscript
fn difference[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]
```

## every {data-api-kind="Function"}

```manuscript
fn every[T](values: List[T], predicate: fn(value: T) -> Bool) -> Bool
```

## fill {data-api-kind="Function"}

```manuscript
fn fill[T](values: List[T], value: T, start: Int, end: Int) -> List[T]
```

## filled {data-api-kind="Function"}

```manuscript
fn filled[T](value: T, count: Int, max_items: Int) -> Result[List[T], LibraryError]
```

## filter {data-api-kind="Function"}

```manuscript
fn filter[T](values: List[T], predicate: fn(value: T) -> Bool) -> List[T]
```

## find {data-api-kind="Function"}

```manuscript
fn find[T](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[T]
```

## find_index {data-api-kind="Function"}

```manuscript
fn find_index[T](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[Int]
```

## find_last {data-api-kind="Function"}

```manuscript
fn find_last[T](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[T]
```

## find_last_index {data-api-kind="Function"}

```manuscript
fn find_last_index[T](values: List[T], predicate: fn(value: T) -> Bool) -> Optional[Int]
```

## first {data-api-kind="Function"}

```manuscript
fn first[T](values: List[T]) -> Optional[T]
```

## flat_map {data-api-kind="Function"}

```manuscript
fn flat_map[T, U](values: List[T], transform: fn(value: T) -> List[U]) -> List[U]
```

## flatten {data-api-kind="Function"}

```manuscript
fn flatten[T](values: List[List[T]]) -> List[T]
```

## fold {data-api-kind="Function"}

```manuscript
fn fold[T, A](values: List[T], initial: A, step: fn(accumulator: A, value: T) -> A) -> A
```

## fold_right {data-api-kind="Function"}

```manuscript
fn fold_right[T, A](values: List[T], initial: A, step: fn(accumulator: A, value: T) -> A) -> A
```

## for_each {data-api-kind="Function"}

```manuscript
fn for_each[T](values: List[T], operation: fn(value: T) -> Unit) -> Unit
```

## group_by {data-api-kind="Function"}

```manuscript
fn group_by[T, K: Hashable](values: List[T], key: fn(value: T) -> K) -> Map[K, List[T]]
```

## index_of {data-api-kind="Function"}

```manuscript
fn index_of[T: Equal](values: List[T], value: T) -> Optional[Int]
```

## intersection {data-api-kind="Function"}

```manuscript
fn intersection[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]
```

## is_disjoint_from {data-api-kind="Function"}

```manuscript
fn is_disjoint_from[T: Hashable](left: Set[T], right: Set[T]) -> Bool
```

## is_empty {data-api-kind="Function"}

```manuscript
fn is_empty[T](values: List[T]) -> Bool
```

## is_subset_of {data-api-kind="Function"}

```manuscript
fn is_subset_of[T: Hashable](left: Set[T], right: Set[T]) -> Bool
```

## is_superset_of {data-api-kind="Function"}

```manuscript
fn is_superset_of[T: Hashable](left: Set[T], right: Set[T]) -> Bool
```

## last {data-api-kind="Function"}

```manuscript
fn last[T](values: List[T]) -> Optional[T]
```

## last_index_of {data-api-kind="Function"}

```manuscript
fn last_index_of[T: Equal](values: List[T], value: T) -> Optional[Int]
```

## list_entries {data-api-kind="Function"}

```manuscript
fn list_entries[T](values: List[T]) -> List[ListEntry[T]]
```

## list_keys {data-api-kind="Function"}

```manuscript
fn list_keys[T](values: List[T]) -> List[Int]
```

## map {data-api-kind="Function"}

```manuscript
fn map[T, U](values: List[T], transform: fn(value: T) -> U) -> List[U]
```

## map_clear {data-api-kind="Function"}

```manuscript
fn map_clear[K: Hashable, V](values: Map[K, V]) -> Map[K, V]
```

## map_entries {data-api-kind="Function"}

```manuscript
fn map_entries[K: Hashable, V](values: Map[K, V]) -> List[MapEntry[K, V]]
```

## map_for_each {data-api-kind="Function"}

```manuscript
fn map_for_each[K: Hashable, V](values: Map[K, V], operation: fn(key: K, value: V) -> Unit) -> Unit
```

## map_from_entries {data-api-kind="Function"}

```manuscript
fn map_from_entries[K: Hashable, V](entries: List[MapEntry[K, V]]) -> Map[K, V]
```

## map_keys {data-api-kind="Function"}

```manuscript
fn map_keys[K: Hashable, V](values: Map[K, V]) -> List[K]
```

## map_merge {data-api-kind="Function"}

```manuscript
fn map_merge[K: Hashable, V](values: Map[K, V], other: Map[K, V]) -> Map[K, V]
```

## map_values {data-api-kind="Function"}

```manuscript
fn map_values[K: Hashable, V](values: Map[K, V]) -> List[V]
```

## map_with_default {data-api-kind="Function"}

```manuscript
fn map_with_default[K: Hashable, V](values: Map[K, V], key: K, value: V) -> Map[K, V]
```

## map_with_default_from {data-api-kind="Function"}

```manuscript
fn map_with_default_from[K: Hashable, V](values: Map[K, V], key: K, create: fn(key: K) -> V) -> Map[K, V]
```

## prepend {data-api-kind="Function"}

```manuscript
fn prepend[T](values: List[T], value: T) -> List[T]
```

## range {data-api-kind="Function"}

```manuscript
fn range(start: Int, end: Int, step: Int, max_items: Int) -> Result[List[Int], LibraryError]
```

## reverse {data-api-kind="Function"}

```manuscript
fn reverse[T](values: List[T]) -> List[T]
```

## set_clear {data-api-kind="Function"}

```manuscript
fn set_clear[T: Hashable](values: Set[T]) -> Set[T]
```

## set_entries {data-api-kind="Function"}

```manuscript
fn set_entries[T: Hashable](values: Set[T]) -> List[List[T]]
```

## set_for_each {data-api-kind="Function"}

```manuscript
fn set_for_each[T: Hashable](values: Set[T], operation: fn(value: T) -> Unit) -> Unit
```

## set_values {data-api-kind="Function"}

```manuscript
fn set_values[T: Hashable](values: Set[T]) -> List[T]
```

## slice {data-api-kind="Function"}

```manuscript
fn slice[T](values: List[T], start: Int, end: Int) -> List[T]
```

## some {data-api-kind="Function"}

```manuscript
fn some[T](values: List[T], predicate: fn(value: T) -> Bool) -> Bool
```

## sort_ints {data-api-kind="Function"}

```manuscript
fn sort_ints(values: List[Int]) -> List[Int]
```

## sort_strings {data-api-kind="Function"}

```manuscript
fn sort_strings(values: List[String]) -> List[String]
```

## sorted {data-api-kind="Function"}

```manuscript
fn sorted[T](values: List[T], compare: fn(left: T, right: T) -> Int) -> List[T]
```

## symmetric_difference {data-api-kind="Function"}

```manuscript
fn symmetric_difference[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]
```

## to_set {data-api-kind="Function"}

```manuscript
fn to_set[T: Hashable](values: List[T]) -> Set[T]
```

## union {data-api-kind="Function"}

```manuscript
fn union[T: Hashable](left: Set[T], right: Set[T]) -> Set[T]
```

## with_value {data-api-kind="Function"}

```manuscript
fn with_value[T](values: List[T], index: Int, value: T) -> List[T]
```

## with_values {data-api-kind="Function"}

```manuscript
fn with_values[T](values: List[T], start: Int, delete_count: Int, replacement: List[T]) -> List[T]
```

## without {data-api-kind="Function"}

```manuscript
fn without[T](values: List[T], index: Int) -> List[T]
```

