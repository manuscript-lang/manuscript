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
operation concat: fn(values: List[T])->List[T]
operation get: fn(index: Int)->Optional[T]
operation length: fn()->Int
```

## Map

Kind: interface.

```text
Map: Map[T, U]
type parameters: T: Hashable, U: Shareable
operation contains: fn(key: T)->Bool
operation get: fn(key: T)->Optional[U]
operation length: fn()->Int
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
operation contains: fn(value: T)->Bool
operation length: fn()->Int
operation with_value: fn(value: T)->Set[T]
operation without: fn(value: T)->Set[T]
```

## difference

Kind: fn.

```text
difference: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## filter

Kind: fn.

```text
filter: fn(values: List[T], predicate: fn(value: T)->Bool)->List[T]
type parameters: T: Shareable
```

## fold

Kind: fn.

```text
fold: fn(values: List[T], initial: A, step: fn(accumulator: A, value: T)->A)->A
type parameters: T: Shareable, A
```

## intersection

Kind: fn.

```text
intersection: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## map

Kind: fn.

```text
map: fn(values: List[T], transform: fn(value: T)->U)->List[U]
type parameters: T: Shareable, U: Shareable
```

## map_keys

Kind: fn.

```text
map_keys: fn(values: Map[K, V])->List[K]
type parameters: K: Hashable, V: Shareable
```

## map_values

Kind: fn.

```text
map_values: fn(values: Map[K, V])->List[V]
type parameters: K: Hashable, V: Shareable
```

## reverse

Kind: fn.

```text
reverse: fn(values: List[T])->List[T]
type parameters: T: Shareable
```

## slice

Kind: fn.

```text
slice: fn(values: List[T], start: Int, end: Int)->List[T]
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

## union

Kind: fn.

```text
union: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

