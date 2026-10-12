+++
title = "collections"
+++

# @std/collections.ms

Import each required symbol with `import Name from "@std/collections.ms"`.

## List

Kind: native.

```text
List: List[T]
type parameters: T: Shareable
operation append: fn(value: T)->List[T]
operation concat: fn(values: List[T])->List[T]
operation get: fn(index: Int)->Optional[T]
operation length: fn()->Int
```

## Map

Kind: native.

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

Kind: native.

```text
Set: Set[T]
type parameters: T: Shareable & Hashable
operation contains: fn(value: T)->Bool
operation length: fn()->Int
operation with_value: fn(value: T)->Set[T]
operation without: fn(value: T)->Set[T]
```

