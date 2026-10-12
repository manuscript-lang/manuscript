+++
title = "collections"
+++

# @std/collections.ms

Import each required symbol with `import Name from "@std/collections.ms"`.

## List

Kind: interface.

```manuscript
List: List[T]
type parameters: T: Shareable
operation append: fn(value: T)->List[T]
operation concat: fn(values: List[T])->List[T]
operation get: fn(index: Int)->Optional[T]
operation length: fn()->Int
```

## Map

Kind: interface.

```manuscript
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

```manuscript
MapEntry: MapEntry[T, U]
type parameters: T: Hashable, U: Shareable
field key: T
field value: U
```

## Set

Kind: interface.

```manuscript
Set: Set[T]
type parameters: T: Shareable & Hashable
operation contains: fn(value: T)->Bool
operation length: fn()->Int
operation with_value: fn(value: T)->Set[T]
operation without: fn(value: T)->Set[T]
```

## difference

Kind: fn.

```manuscript
difference: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## filter

Kind: fn.

```manuscript
filter: fn(values: List[T], predicate: fn(value: T)->Bool)->List[T]
type parameters: T: Shareable
```

## fold

Kind: fn.

```manuscript
fold: fn(values: List[T], initial: A, step: fn(accumulator: A, value: T)->A)->A
type parameters: T: Shareable, A
```

## intersection

Kind: fn.

```manuscript
intersection: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

## map

Kind: fn.

```manuscript
map: fn(values: List[T], transform: fn(value: T)->U)->List[U]
type parameters: T: Shareable, U: Shareable
```

## map_keys

Kind: fn.

```manuscript
map_keys: fn(values: Map[K, V])->List[K]
type parameters: K: Hashable, V: Shareable
```

## map_values

Kind: fn.

```manuscript
map_values: fn(values: Map[K, V])->List[V]
type parameters: K: Hashable, V: Shareable
```

## reverse

Kind: fn.

```manuscript
reverse: fn(values: List[T])->List[T]
type parameters: T: Shareable
```

## slice

Kind: fn.

```manuscript
slice: fn(values: List[T], start: Int, end: Int)->List[T]
type parameters: T: Shareable
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
type parameters: T: Shareable
```

## union

Kind: fn.

```manuscript
union: fn(left: Set[T], right: Set[T])->Set[T]
type parameters: T: Hashable
```

