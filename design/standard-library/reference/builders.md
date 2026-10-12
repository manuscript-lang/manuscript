+++
title = "builders"
+++

# @std/builders.ms

Import each required symbol with `import Name from "@std/builders.ms"`.

## BytesBuilder {data-api-kind="Native type"}

```manuscript
type BytesBuilder:
    fn append(value: Int) -> Unit
    fn concat(values: Bytes) -> Unit
    fn freeze() -> Bytes
```

## ListBuilder {data-api-kind="Native type"}

```manuscript
type ListBuilder[T]:
    fn append(value: T) -> Unit
    fn freeze() -> List[T]
```

## MapBuilder {data-api-kind="Native type"}

```manuscript
type MapBuilder[T: Hashable, U]:
    fn freeze() -> Map[T, U]
    fn with_entry(key: T, value: U) -> Unit
```

## SetBuilder {data-api-kind="Native type"}

```manuscript
type SetBuilder[T: Hashable]:
    fn freeze() -> Set[T]
    fn with_value(value: T) -> Unit
```

## StringBuilder {data-api-kind="Native type"}

```manuscript
type StringBuilder:
    fn append(value: String) -> Unit
    fn freeze() -> String
```

