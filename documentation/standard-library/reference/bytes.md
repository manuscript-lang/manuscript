+++
title = "bytes"
+++

# @std/bytes.ms

Import each required symbol with `import Name from "@std/bytes.ms"`.

## Bytes {data-api-kind="Native type"}

```manuscript
type Bytes:
    values: List[Int]
    fn clone() -> Bytes
    fn contains(value: Bytes) -> Bool
    fn slice(start: Int, end: Int) -> Bytes
    fn at(index: Int) -> Optional[Int]
    fn index_of(value: Bytes) -> Optional[Int]
    fn last_index_of(value: Bytes) -> Optional[Int]
    fn starts_with(value: Bytes) -> Bool
    fn ends_with(value: Bytes) -> Bool
    fn reverse() -> Bytes
    fn with_value(index: Int, value: Int) -> Bytes
    fn is_empty() -> Bool
    fn concat(values: Bytes) -> Bytes
    fn length() -> Int
    fn to_text() -> Optional[String]
```

## BytesBuilder {data-api-kind="Native type"}

```manuscript
type BytesBuilder:
    fn append(value: Int) -> Unit
    fn concat(values: Bytes) -> Unit
    fn freeze() -> Bytes
```

## values {data-api-kind="Function"}

```manuscript
fn values(data: Bytes) -> List[Int]
```

