+++
title = "builders"
+++

# @std/builders.ms

Import each required symbol with `import Name from "@std/builders.ms"`.

## BytesBuilder {data-api-kind="Interface"}

```manuscript
BytesBuilder: BytesBuilder
operation append: fn(value: Int)->Unit
operation concat: fn(values: Bytes)->Unit
operation freeze: fn()->Bytes
```

## ListBuilder {data-api-kind="Interface"}

```manuscript
ListBuilder: ListBuilder[T]
type parameters: T
operation append: fn(value: T)->Unit
operation freeze: fn()->List[T]
```

## MapBuilder {data-api-kind="Interface"}

```manuscript
MapBuilder: MapBuilder[T, U]
type parameters: T: Hashable, U
operation freeze: fn()->Map[T, U]
operation with_entry: fn(key: T, value: U)->Unit
```

## SetBuilder {data-api-kind="Interface"}

```manuscript
SetBuilder: SetBuilder[T]
type parameters: T: Hashable
operation freeze: fn()->Set[T]
operation with_value: fn(value: T)->Unit
```

## StringBuilder {data-api-kind="Interface"}

```manuscript
StringBuilder: StringBuilder
operation append: fn(value: String)->Unit
operation freeze: fn()->String
```

