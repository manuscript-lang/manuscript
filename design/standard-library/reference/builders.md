+++
title = "builders"
+++

# @std/builders.ms

Import each required symbol with `import Name from "@std/builders.ms"`.

## BytesBuilder

Kind: native.

```text
BytesBuilder: BytesBuilder
operation append: fn(value: Int)->Unit
operation concat: fn(values: Bytes)->Unit
operation freeze: fn()->Bytes
```

## ListBuilder

Kind: native.

```text
ListBuilder: ListBuilder[T]
type parameters: T: Shareable
operation append: fn(value: T)->Unit
operation freeze: fn()->List[T]
```

## MapBuilder

Kind: native.

```text
MapBuilder: MapBuilder[T, U]
type parameters: T: Hashable, U: Shareable
operation freeze: fn()->Map[T, U]
operation with_entry: fn(key: T, value: U)->Unit
```

## SetBuilder

Kind: native.

```text
SetBuilder: SetBuilder[T]
type parameters: T: Hashable
operation freeze: fn()->Set[T]
operation with_value: fn(value: T)->Unit
```

## StringBuilder

Kind: native.

```text
StringBuilder: StringBuilder
operation append: fn(value: String)->Unit
operation freeze: fn()->String
```

