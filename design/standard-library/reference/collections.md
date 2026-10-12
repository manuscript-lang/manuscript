+++
title = "collections"
+++

# @std/collections.ms

Import each required symbol with `import Name from "@std/collections.ms"`.

## List {data-api-kind="Interface"}

```manuscript
List: List[T]
type parameters: T: Shareable
operation append: fn(value: T)->List[T]
operation at: fn(index: Int)->Optional[T]
operation concat: fn(values: List[T])->List[T]
operation contains: fn(value: T)->Bool
operation copy_within: fn(target: Int, start: Int, end: Int)->List[T]
operation entries: fn()->List[ListEntry[T]]
operation every: fn(predicate: fn(value: T)->Bool)->Bool
operation fill: fn(value: T, start: Int, end: Int)->List[T]
operation filter: fn(predicate: fn(value: T)->Bool)->List[T]
operation find: fn(predicate: fn(value: T)->Bool)->Optional[T]
operation find_index: fn(predicate: fn(value: T)->Bool)->Optional[Int]
operation find_last: fn(predicate: fn(value: T)->Bool)->Optional[T]
operation find_last_index: fn(predicate: fn(value: T)->Bool)->Optional[Int]
operation first: fn()->Optional[T]
operation flat_map[U: Shareable]: fn(transform: fn(value: T)->List[U])->List[U]
operation fold[A]: fn(initial: A, step: fn(accumulator: A, value: T)->A)->A
operation fold_right[A]: fn(initial: A, step: fn(accumulator: A, value: T)->A)->A
operation for_each: fn(operation: fn(value: T)->Unit)->Unit
operation get: fn(index: Int)->Optional[T]
operation group_by[K: Hashable]: fn(key: fn(value: T)->K)->Map[K, List[T]]
operation index_of: fn(value: T)->Optional[Int]
operation is_empty: fn()->Bool
operation join: fn(separator: String)->String
operation keys: fn()->List[Int]
operation last: fn()->Optional[T]
operation last_index_of: fn(value: T)->Optional[Int]
operation length: fn()->Int
operation map[U: Shareable]: fn(transform: fn(value: T)->U)->List[U]
operation prepend: fn(value: T)->List[T]
operation reverse: fn()->List[T]
operation slice: fn(start: Int, end: Int)->List[T]
operation some: fn(predicate: fn(value: T)->Bool)->Bool
operation sorted: fn(compare: fn(left: T, right: T)->Int)->List[T]
operation to_set: fn()->Set[T]
operation with_value: fn(index: Int, value: T)->List[T]
operation with_values: fn(start: Int, delete_count: Int, replacement: List[T])->List[T]
operation without: fn(index: Int)->List[T]
```

## ListEntry {data-api-kind="Record"}

```manuscript
ListEntry: ListEntry[T]
type parameters: T: Shareable
field index: Int
field value: T
```

## Map {data-api-kind="Interface"}

```manuscript
Map: Map[T, U]
type parameters: T: Hashable, U: Shareable
operation clear: fn()->Map[T, U]
operation contains: fn(key: T)->Bool
operation entries: fn()->List[MapEntry[T, U]]
operation for_each: fn(operation: fn(key: T, value: U)->Unit)->Unit
operation get: fn(key: T)->Optional[U]
operation keys: fn()->List[T]
operation length: fn()->Int
operation merge: fn(other: Map[T, U])->Map[T, U]
operation values: fn()->List[U]
operation with_default: fn(key: T, value: U)->Map[T, U]
operation with_default_from: fn(key: T, create: fn(key: T)->U)->Map[T, U]
operation with_entry: fn(key: T, value: U)->Map[T, U]
operation without: fn(key: T)->Map[T, U]
```

## MapEntry {data-api-kind="Record"}

```manuscript
MapEntry: MapEntry[T, U]
type parameters: T: Hashable, U: Shareable
field key: T
field value: U
```

## Set {data-api-kind="Interface"}

```manuscript
Set: Set[T]
type parameters: T: Shareable & Hashable
operation clear: fn()->Set[T]
operation contains: fn(value: T)->Bool
operation difference: fn(right: Set[T])->Set[T]
operation entries: fn()->List[List[T]]
operation for_each: fn(operation: fn(value: T)->Unit)->Unit
operation intersection: fn(right: Set[T])->Set[T]
operation is_disjoint_from: fn(right: Set[T])->Bool
operation is_subset_of: fn(right: Set[T])->Bool
operation is_superset_of: fn(right: Set[T])->Bool
operation length: fn()->Int
operation symmetric_difference: fn(right: Set[T])->Set[T]
operation union: fn(right: Set[T])->Set[T]
operation values: fn()->List[T]
operation with_value: fn(value: T)->Set[T]
operation without: fn(value: T)->Set[T]
```

## at {data-api-kind="Function"}

```manuscript
at: fn(values: List[T], index: Int)->Optional[T]
type parameters: T: Shareable
```

## contains {data-api-kind="Function"}

```manuscript
contains: fn(values: List[T], value: T)->Bool
type parameters: T: Shareable & Equal
```

## copy_within {data-api-kind="Function"}

```manuscript
copy_within: fn(values: List[T], target: Int, start: Int, end: Int)->List[T]
type parameters: T: Shareable
```

## difference {data-api-kind="Function"}

```manuscript
difference: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## every {data-api-kind="Function"}

```manuscript
every: fn(values: List[T], predicate: fn(value: T)->Bool)->Bool
type parameters: T: Shareable
```

## fill {data-api-kind="Function"}

```manuscript
fill: fn(values: List[T], value: T, start: Int, end: Int)->List[T]
type parameters: T: Shareable
```

## filled {data-api-kind="Function"}

```manuscript
filled: fn(value: T, count: Int, max_items: Int)->Result[List[T], LibraryError]
type parameters: T: Shareable
```

## filter {data-api-kind="Function"}

```manuscript
filter: fn(values: List[T], predicate: fn(value: T)->Bool)->List[T]
type parameters: T: Shareable
```

## find {data-api-kind="Function"}

```manuscript
find: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[T]
type parameters: T: Shareable
```

## find_index {data-api-kind="Function"}

```manuscript
find_index: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[Int]
type parameters: T: Shareable
```

## find_last {data-api-kind="Function"}

```manuscript
find_last: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[T]
type parameters: T: Shareable
```

## find_last_index {data-api-kind="Function"}

```manuscript
find_last_index: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[Int]
type parameters: T: Shareable
```

## first {data-api-kind="Function"}

```manuscript
first: fn(values: List[T])->Optional[T]
type parameters: T: Shareable
```

## flat_map {data-api-kind="Function"}

```manuscript
flat_map: fn(values: List[T], transform: fn(value: T)->List[U])->List[U]
type parameters: T: Shareable, U: Shareable
```

## flatten {data-api-kind="Function"}

```manuscript
flatten: fn(values: List[List[T]])->List[T]
type parameters: T: Shareable
```

## fold {data-api-kind="Function"}

```manuscript
fold: fn(values: List[T], initial: A, step: fn(accumulator: A, value: T)->A)->A
type parameters: T: Shareable, A
```

## fold_right {data-api-kind="Function"}

```manuscript
fold_right: fn(values: List[T], initial: A, step: fn(accumulator: A, value: T)->A)->A
type parameters: T: Shareable, A
```

## for_each {data-api-kind="Function"}

```manuscript
for_each: fn(values: List[T], operation: fn(value: T)->Unit)->Unit
type parameters: T: Shareable
```

## group_by {data-api-kind="Function"}

```manuscript
group_by: fn(values: List[T], key: fn(value: T)->K)->Map[K, List[T]]
type parameters: T: Shareable, K: Hashable
```

## index_of {data-api-kind="Function"}

```manuscript
index_of: fn(values: List[T], value: T)->Optional[Int]
type parameters: T: Shareable & Equal
```

## intersection {data-api-kind="Function"}

```manuscript
intersection: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## is_disjoint_from {data-api-kind="Function"}

```manuscript
is_disjoint_from: fn(left: Set[T], right: Set[T])->Bool
type parameters: T: Hashable
```

## is_empty {data-api-kind="Function"}

```manuscript
is_empty: fn(values: List[T])->Bool
type parameters: T: Shareable
```

## is_subset_of {data-api-kind="Function"}

```manuscript
is_subset_of: fn(left: Set[T], right: Set[T])->Bool
type parameters: T: Hashable
```

## is_superset_of {data-api-kind="Function"}

```manuscript
is_superset_of: fn(left: Set[T], right: Set[T])->Bool
type parameters: T: Hashable
```

## last {data-api-kind="Function"}

```manuscript
last: fn(values: List[T])->Optional[T]
type parameters: T: Shareable
```

## last_index_of {data-api-kind="Function"}

```manuscript
last_index_of: fn(values: List[T], value: T)->Optional[Int]
type parameters: T: Shareable & Equal
```

## list_entries {data-api-kind="Function"}

```manuscript
list_entries: fn(values: List[T])->List[ListEntry[T]]
type parameters: T: Shareable
```

## list_keys {data-api-kind="Function"}

```manuscript
list_keys: fn(values: List[T])->List[Int]
type parameters: T: Shareable
```

## map {data-api-kind="Function"}

```manuscript
map: fn(values: List[T], transform: fn(value: T)->U)->List[U]
type parameters: T: Shareable, U: Shareable
```

## map_clear {data-api-kind="Function"}

```manuscript
map_clear: fn(values: Map[K, V])->Map[K, V]
type parameters: K: Hashable, V: Shareable
```

## map_entries {data-api-kind="Function"}

```manuscript
map_entries: fn(values: Map[K, V])->List[MapEntry[K, V]]
type parameters: K: Hashable, V: Shareable
```

## map_for_each {data-api-kind="Function"}

```manuscript
map_for_each: fn(values: Map[K, V], operation: fn(key: K, value: V)->Unit)->Unit
type parameters: K: Hashable, V: Shareable
```

## map_from_entries {data-api-kind="Function"}

```manuscript
map_from_entries: fn(entries: List[MapEntry[K, V]])->Map[K, V]
type parameters: K: Hashable, V: Shareable
```

## map_keys {data-api-kind="Function"}

```manuscript
map_keys: fn(values: Map[K, V])->List[K]
type parameters: K: Hashable, V: Shareable
```

## map_merge {data-api-kind="Function"}

```manuscript
map_merge: fn(values: Map[K, V], other: Map[K, V])->Map[K, V]
type parameters: K: Hashable, V: Shareable
```

## map_values {data-api-kind="Function"}

```manuscript
map_values: fn(values: Map[K, V])->List[V]
type parameters: K: Hashable, V: Shareable
```

## map_with_default {data-api-kind="Function"}

```manuscript
map_with_default: fn(values: Map[K, V], key: K, value: V)->Map[K, V]
type parameters: K: Hashable, V: Shareable
```

## map_with_default_from {data-api-kind="Function"}

```manuscript
map_with_default_from: fn(values: Map[K, V], key: K, create: fn(key: K)->V)->Map[K, V]
type parameters: K: Hashable, V: Shareable
```

## prepend {data-api-kind="Function"}

```manuscript
prepend: fn(values: List[T], value: T)->List[T]
type parameters: T: Shareable
```

## range {data-api-kind="Function"}

```manuscript
range: fn(start: Int, end: Int, step: Int, max_items: Int)->Result[List[Int], LibraryError]
```

## reverse {data-api-kind="Function"}

```manuscript
reverse: fn(values: List[T])->List[T]
type parameters: T: Shareable
```

## set_clear {data-api-kind="Function"}

```manuscript
set_clear: fn(values: Set[T])->Set[T]
type parameters: T: Hashable
```

## set_entries {data-api-kind="Function"}

```manuscript
set_entries: fn(values: Set[T])->List[List[T]]
type parameters: T: Hashable
```

## set_for_each {data-api-kind="Function"}

```manuscript
set_for_each: fn(values: Set[T], operation: fn(value: T)->Unit)->Unit
type parameters: T: Hashable
```

## set_values {data-api-kind="Function"}

```manuscript
set_values: fn(values: Set[T])->List[T]
type parameters: T: Hashable
```

## slice {data-api-kind="Function"}

```manuscript
slice: fn(values: List[T], start: Int, end: Int)->List[T]
type parameters: T: Shareable
```

## some {data-api-kind="Function"}

```manuscript
some: fn(values: List[T], predicate: fn(value: T)->Bool)->Bool
type parameters: T: Shareable
```

## sort_ints {data-api-kind="Function"}

```manuscript
sort_ints: fn(values: List[Int])->List[Int]
```

## sort_strings {data-api-kind="Function"}

```manuscript
sort_strings: fn(values: List[String])->List[String]
```

## sorted {data-api-kind="Function"}

```manuscript
sorted: fn(values: List[T], compare: fn(left: T, right: T)->Int)->List[T]
type parameters: T: Shareable
```

## symmetric_difference {data-api-kind="Function"}

```manuscript
symmetric_difference: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## to_set {data-api-kind="Function"}

```manuscript
to_set: fn(values: List[T])->Set[T]
type parameters: T: Shareable & Hashable
```

## union {data-api-kind="Function"}

```manuscript
union: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## with_value {data-api-kind="Function"}

```manuscript
with_value: fn(values: List[T], index: Int, value: T)->List[T]
type parameters: T: Shareable
```

## with_values {data-api-kind="Function"}

```manuscript
with_values: fn(values: List[T], start: Int, delete_count: Int, replacement: List[T])->List[T]
type parameters: T: Shareable
```

## without {data-api-kind="Function"}

```manuscript
without: fn(values: List[T], index: Int)->List[T]
type parameters: T: Shareable
```

