+++
title = "collections"
+++

# @std/collections.ms

Import each required symbol with `import Name from "@std/collections.ms"`.

## List

Kind: interface.

```text
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

## ListEntry

Kind: record.

```text
ListEntry: ListEntry[T]
type parameters: T: Shareable
field index: Int
field value: T
```

## Map

Kind: interface.

```text
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

## MapEntry

Kind: record.

```text
MapEntry: MapEntry[T, U]
type parameters: T: Hashable, U: Shareable
field key: T
field value: U
```

## Set

Kind: interface.

```text
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

## at

Kind: fn.

```text
at: fn(values: List[T], index: Int)->Optional[T]
type parameters: T: Shareable
```

## contains

Kind: fn.

```text
contains: fn(values: List[T], value: T)->Bool
type parameters: T: Shareable & Equal
```

## copy_within

Kind: fn.

```text
copy_within: fn(values: List[T], target: Int, start: Int, end: Int)->List[T]
type parameters: T: Shareable
```

## difference

Kind: fn.

```text
difference: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## every

Kind: fn.

```text
every: fn(values: List[T], predicate: fn(value: T)->Bool)->Bool
type parameters: T: Shareable
```

## fill

Kind: fn.

```text
fill: fn(values: List[T], value: T, start: Int, end: Int)->List[T]
type parameters: T: Shareable
```

## filled

Kind: fn.

```text
filled: fn(value: T, count: Int, max_items: Int)->Result[List[T], LibraryError]
type parameters: T: Shareable
```

## filter

Kind: fn.

```text
filter: fn(values: List[T], predicate: fn(value: T)->Bool)->List[T]
type parameters: T: Shareable
```

## find

Kind: fn.

```text
find: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[T]
type parameters: T: Shareable
```

## find_index

Kind: fn.

```text
find_index: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[Int]
type parameters: T: Shareable
```

## find_last

Kind: fn.

```text
find_last: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[T]
type parameters: T: Shareable
```

## find_last_index

Kind: fn.

```text
find_last_index: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[Int]
type parameters: T: Shareable
```

## first

Kind: fn.

```text
first: fn(values: List[T])->Optional[T]
type parameters: T: Shareable
```

## flat_map

Kind: fn.

```text
flat_map: fn(values: List[T], transform: fn(value: T)->List[U])->List[U]
type parameters: T: Shareable, U: Shareable
```

## flatten

Kind: fn.

```text
flatten: fn(values: List[List[T]])->List[T]
type parameters: T: Shareable
```

## fold

Kind: fn.

```text
fold: fn(values: List[T], initial: A, step: fn(accumulator: A, value: T)->A)->A
type parameters: T: Shareable, A
```

## fold_right

Kind: fn.

```text
fold_right: fn(values: List[T], initial: A, step: fn(accumulator: A, value: T)->A)->A
type parameters: T: Shareable, A
```

## for_each

Kind: fn.

```text
for_each: fn(values: List[T], operation: fn(value: T)->Unit)->Unit
type parameters: T: Shareable
```

## group_by

Kind: fn.

```text
group_by: fn(values: List[T], key: fn(value: T)->K)->Map[K, List[T]]
type parameters: T: Shareable, K: Hashable
```

## index_of

Kind: fn.

```text
index_of: fn(values: List[T], value: T)->Optional[Int]
type parameters: T: Shareable & Equal
```

## intersection

Kind: fn.

```text
intersection: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## is_disjoint_from

Kind: fn.

```text
is_disjoint_from: fn(left: Set[T], right: Set[T])->Bool
type parameters: T: Hashable
```

## is_empty

Kind: fn.

```text
is_empty: fn(values: List[T])->Bool
type parameters: T: Shareable
```

## is_subset_of

Kind: fn.

```text
is_subset_of: fn(left: Set[T], right: Set[T])->Bool
type parameters: T: Hashable
```

## is_superset_of

Kind: fn.

```text
is_superset_of: fn(left: Set[T], right: Set[T])->Bool
type parameters: T: Hashable
```

## last

Kind: fn.

```text
last: fn(values: List[T])->Optional[T]
type parameters: T: Shareable
```

## last_index_of

Kind: fn.

```text
last_index_of: fn(values: List[T], value: T)->Optional[Int]
type parameters: T: Shareable & Equal
```

## list_entries

Kind: fn.

```text
list_entries: fn(values: List[T])->List[ListEntry[T]]
type parameters: T: Shareable
```

## list_keys

Kind: fn.

```text
list_keys: fn(values: List[T])->List[Int]
type parameters: T: Shareable
```

## map

Kind: fn.

```text
map: fn(values: List[T], transform: fn(value: T)->U)->List[U]
type parameters: T: Shareable, U: Shareable
```

## map_clear

Kind: fn.

```text
map_clear: fn(values: Map[K, V])->Map[K, V]
type parameters: K: Hashable, V: Shareable
```

## map_entries

Kind: fn.

```text
map_entries: fn(values: Map[K, V])->List[MapEntry[K, V]]
type parameters: K: Hashable, V: Shareable
```

## map_for_each

Kind: fn.

```text
map_for_each: fn(values: Map[K, V], operation: fn(key: K, value: V)->Unit)->Unit
type parameters: K: Hashable, V: Shareable
```

## map_from_entries

Kind: fn.

```text
map_from_entries: fn(entries: List[MapEntry[K, V]])->Map[K, V]
type parameters: K: Hashable, V: Shareable
```

## map_keys

Kind: fn.

```text
map_keys: fn(values: Map[K, V])->List[K]
type parameters: K: Hashable, V: Shareable
```

## map_merge

Kind: fn.

```text
map_merge: fn(values: Map[K, V], other: Map[K, V])->Map[K, V]
type parameters: K: Hashable, V: Shareable
```

## map_values

Kind: fn.

```text
map_values: fn(values: Map[K, V])->List[V]
type parameters: K: Hashable, V: Shareable
```

## map_with_default

Kind: fn.

```text
map_with_default: fn(values: Map[K, V], key: K, value: V)->Map[K, V]
type parameters: K: Hashable, V: Shareable
```

## map_with_default_from

Kind: fn.

```text
map_with_default_from: fn(values: Map[K, V], key: K, create: fn(key: K)->V)->Map[K, V]
type parameters: K: Hashable, V: Shareable
```

## prepend

Kind: fn.

```text
prepend: fn(values: List[T], value: T)->List[T]
type parameters: T: Shareable
```

## range

Kind: fn.

```text
range: fn(start: Int, end: Int, step: Int, max_items: Int)->Result[List[Int], LibraryError]
```

## reverse

Kind: fn.

```text
reverse: fn(values: List[T])->List[T]
type parameters: T: Shareable
```

## set_clear

Kind: fn.

```text
set_clear: fn(values: Set[T])->Set[T]
type parameters: T: Hashable
```

## set_entries

Kind: fn.

```text
set_entries: fn(values: Set[T])->List[List[T]]
type parameters: T: Hashable
```

## set_for_each

Kind: fn.

```text
set_for_each: fn(values: Set[T], operation: fn(value: T)->Unit)->Unit
type parameters: T: Hashable
```

## set_values

Kind: fn.

```text
set_values: fn(values: Set[T])->List[T]
type parameters: T: Hashable
```

## slice

Kind: fn.

```text
slice: fn(values: List[T], start: Int, end: Int)->List[T]
type parameters: T: Shareable
```

## some

Kind: fn.

```text
some: fn(values: List[T], predicate: fn(value: T)->Bool)->Bool
type parameters: T: Shareable
```

## sort_ints

Kind: fn.

```text
sort_ints: fn(values: List[Int])->List[Int]
```

## sort_strings

Kind: fn.

```text
sort_strings: fn(values: List[String])->List[String]
```

## sorted

Kind: fn.

```text
sorted: fn(values: List[T], compare: fn(left: T, right: T)->Int)->List[T]
type parameters: T: Shareable
```

## symmetric_difference

Kind: fn.

```text
symmetric_difference: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## to_set

Kind: fn.

```text
to_set: fn(values: List[T])->Set[T]
type parameters: T: Shareable & Hashable
```

## union

Kind: fn.

```text
union: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## with_value

Kind: fn.

```text
with_value: fn(values: List[T], index: Int, value: T)->List[T]
type parameters: T: Shareable
```

## with_values

Kind: fn.

```text
with_values: fn(values: List[T], start: Int, delete_count: Int, replacement: List[T])->List[T]
type parameters: T: Shareable
```

## without

Kind: fn.

```text
without: fn(values: List[T], index: Int)->List[T]
type parameters: T: Shareable
```

