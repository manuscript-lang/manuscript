+++
title = "collections"
+++

# @std/collections.ms

Import each required symbol with `import Name from "@std/collections.ms"`.

## List

Kind: interface.

```manuscript
List: List[T]
type parameters: T
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
operation flat_map[U]: fn(transform: fn(value: T)->List[U])->List[U]
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
operation map[U]: fn(transform: fn(value: T)->U)->List[U]
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

```manuscript
ListEntry: ListEntry[T]
type parameters: T
field index: Int
field value: T
```

## Map

Kind: interface.

```manuscript
Map: Map[T, U]
type parameters: T: Hashable, U
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

```manuscript
MapEntry: MapEntry[T, U]
type parameters: T: Hashable, U
field key: T
field value: U
```

## Set

Kind: interface.

```manuscript
Set: Set[T]
type parameters: T: Hashable
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

```manuscript
at: fn(values: List[T], index: Int)->Optional[T]
type parameters: T
```

## contains

Kind: fn.

```manuscript
contains: fn(values: List[T], value: T)->Bool
type parameters: T: Equal
```

## copy_within

Kind: fn.

```manuscript
copy_within: fn(values: List[T], target: Int, start: Int, end: Int)->List[T]
type parameters: T
```

## difference

Kind: fn.

```manuscript
difference: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## every

Kind: fn.

```manuscript
every: fn(values: List[T], predicate: fn(value: T)->Bool)->Bool
type parameters: T
```

## fill

Kind: fn.

```manuscript
fill: fn(values: List[T], value: T, start: Int, end: Int)->List[T]
type parameters: T
```

## filled

Kind: fn.

```manuscript
filled: fn(value: T, count: Int, max_items: Int)->Result[List[T], LibraryError]
type parameters: T
```

## filter

Kind: fn.

```manuscript
filter: fn(values: List[T], predicate: fn(value: T)->Bool)->List[T]
type parameters: T
```

## find

Kind: fn.

```manuscript
find: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[T]
type parameters: T
```

## find_index

Kind: fn.

```manuscript
find_index: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[Int]
type parameters: T
```

## find_last

Kind: fn.

```manuscript
find_last: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[T]
type parameters: T
```

## find_last_index

Kind: fn.

```manuscript
find_last_index: fn(values: List[T], predicate: fn(value: T)->Bool)->Optional[Int]
type parameters: T
```

## first

Kind: fn.

```manuscript
first: fn(values: List[T])->Optional[T]
type parameters: T
```

## flat_map

Kind: fn.

```manuscript
flat_map: fn(values: List[T], transform: fn(value: T)->List[U])->List[U]
type parameters: T, U
```

## flatten

Kind: fn.

```manuscript
flatten: fn(values: List[List[T]])->List[T]
type parameters: T
```

## fold

Kind: fn.

```manuscript
fold: fn(values: List[T], initial: A, step: fn(accumulator: A, value: T)->A)->A
type parameters: T, A
```

## fold_right

Kind: fn.

```manuscript
fold_right: fn(values: List[T], initial: A, step: fn(accumulator: A, value: T)->A)->A
type parameters: T, A
```

## for_each

Kind: fn.

```manuscript
for_each: fn(values: List[T], operation: fn(value: T)->Unit)->Unit
type parameters: T
```

## group_by

Kind: fn.

```manuscript
group_by: fn(values: List[T], key: fn(value: T)->K)->Map[K, List[T]]
type parameters: T, K: Hashable
```

## index_of

Kind: fn.

```manuscript
index_of: fn(values: List[T], value: T)->Optional[Int]
type parameters: T: Equal
```

## intersection

Kind: fn.

```manuscript
intersection: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## is_disjoint_from

Kind: fn.

```manuscript
is_disjoint_from: fn(left: Set[T], right: Set[T])->Bool
type parameters: T: Hashable
```

## is_empty

Kind: fn.

```manuscript
is_empty: fn(values: List[T])->Bool
type parameters: T
```

## is_subset_of

Kind: fn.

```manuscript
is_subset_of: fn(left: Set[T], right: Set[T])->Bool
type parameters: T: Hashable
```

## is_superset_of

Kind: fn.

```manuscript
is_superset_of: fn(left: Set[T], right: Set[T])->Bool
type parameters: T: Hashable
```

## last

Kind: fn.

```manuscript
last: fn(values: List[T])->Optional[T]
type parameters: T
```

## last_index_of

Kind: fn.

```manuscript
last_index_of: fn(values: List[T], value: T)->Optional[Int]
type parameters: T: Equal
```

## list_entries

Kind: fn.

```manuscript
list_entries: fn(values: List[T])->List[ListEntry[T]]
type parameters: T
```

## list_keys

Kind: fn.

```manuscript
list_keys: fn(values: List[T])->List[Int]
type parameters: T
```

## map

Kind: fn.

```manuscript
map: fn(values: List[T], transform: fn(value: T)->U)->List[U]
type parameters: T, U
```

## map_clear

Kind: fn.

```manuscript
map_clear: fn(values: Map[K, V])->Map[K, V]
type parameters: K: Hashable, V
```

## map_entries

Kind: fn.

```manuscript
map_entries: fn(values: Map[K, V])->List[MapEntry[K, V]]
type parameters: K: Hashable, V
```

## map_for_each

Kind: fn.

```manuscript
map_for_each: fn(values: Map[K, V], operation: fn(key: K, value: V)->Unit)->Unit
type parameters: K: Hashable, V
```

## map_from_entries

Kind: fn.

```manuscript
map_from_entries: fn(entries: List[MapEntry[K, V]])->Map[K, V]
type parameters: K: Hashable, V
```

## map_keys

Kind: fn.

```manuscript
map_keys: fn(values: Map[K, V])->List[K]
type parameters: K: Hashable, V
```

## map_merge

Kind: fn.

```manuscript
map_merge: fn(values: Map[K, V], other: Map[K, V])->Map[K, V]
type parameters: K: Hashable, V
```

## map_values

Kind: fn.

```manuscript
map_values: fn(values: Map[K, V])->List[V]
type parameters: K: Hashable, V
```

## map_with_default

Kind: fn.

```manuscript
map_with_default: fn(values: Map[K, V], key: K, value: V)->Map[K, V]
type parameters: K: Hashable, V
```

## map_with_default_from

Kind: fn.

```manuscript
map_with_default_from: fn(values: Map[K, V], key: K, create: fn(key: K)->V)->Map[K, V]
type parameters: K: Hashable, V
```

## prepend

Kind: fn.

```manuscript
prepend: fn(values: List[T], value: T)->List[T]
type parameters: T
```

## range

Kind: fn.

```manuscript
range: fn(start: Int, end: Int, step: Int, max_items: Int)->Result[List[Int], LibraryError]
```

## reverse

Kind: fn.

```manuscript
reverse: fn(values: List[T])->List[T]
type parameters: T
```

## set_clear

Kind: fn.

```manuscript
set_clear: fn(values: Set[T])->Set[T]
type parameters: T: Hashable
```

## set_entries

Kind: fn.

```manuscript
set_entries: fn(values: Set[T])->List[List[T]]
type parameters: T: Hashable
```

## set_for_each

Kind: fn.

```manuscript
set_for_each: fn(values: Set[T], operation: fn(value: T)->Unit)->Unit
type parameters: T: Hashable
```

## set_values

Kind: fn.

```manuscript
set_values: fn(values: Set[T])->List[T]
type parameters: T: Hashable
```

## slice

Kind: fn.

```manuscript
slice: fn(values: List[T], start: Int, end: Int)->List[T]
type parameters: T
```

## some

Kind: fn.

```manuscript
some: fn(values: List[T], predicate: fn(value: T)->Bool)->Bool
type parameters: T
```

## sort_ints

Kind: fn.

```manuscript
sort_ints: fn(values: List[Int])->List[Int]
```

## sort_strings

Kind: fn.

```manuscript
sort_strings: fn(values: List[String])->List[String]
```

## sorted

Kind: fn.

```manuscript
sorted: fn(values: List[T], compare: fn(left: T, right: T)->Int)->List[T]
type parameters: T
```

## symmetric_difference

Kind: fn.

```manuscript
symmetric_difference: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## to_set

Kind: fn.

```manuscript
to_set: fn(values: List[T])->Set[T]
type parameters: T: Hashable
```

## union

Kind: fn.

```manuscript
union: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## with_value

Kind: fn.

```manuscript
with_value: fn(values: List[T], index: Int, value: T)->List[T]
type parameters: T
```

## with_values

Kind: fn.

```manuscript
with_values: fn(values: List[T], start: Int, delete_count: Int, replacement: List[T])->List[T]
type parameters: T
```

## without

Kind: fn.

```manuscript
without: fn(values: List[T], index: Int)->List[T]
type parameters: T
```

