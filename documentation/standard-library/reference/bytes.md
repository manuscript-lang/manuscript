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
    fn get(index: Int) -> Optional[Int]
    fn length() -> Int
    fn to_text() -> Optional[String]
```

## at {data-api-kind="Function"}

```manuscript
fn at(data: Bytes, index: Int) -> Optional[Int]
```

## contains {data-api-kind="Function"}

```manuscript
fn contains(data: Bytes, value: Bytes) -> Bool
```

## ends_with {data-api-kind="Function"}

```manuscript
fn ends_with(data: Bytes, value: Bytes) -> Bool
```

## index_of {data-api-kind="Function"}

```manuscript
fn index_of(data: Bytes, value: Bytes) -> Optional[Int]
```

## is_empty {data-api-kind="Function"}

```manuscript
fn is_empty(data: Bytes) -> Bool
```

## last_index_of {data-api-kind="Function"}

```manuscript
fn last_index_of(data: Bytes, value: Bytes) -> Optional[Int]
```

## reverse {data-api-kind="Function"}

```manuscript
fn reverse(data: Bytes) -> Bytes
```

## slice {data-api-kind="Function"}

```manuscript
fn slice(data: Bytes, start: Int, end: Int) -> Bytes
```

## starts_with {data-api-kind="Function"}

```manuscript
fn starts_with(data: Bytes, value: Bytes) -> Bool
```

## values {data-api-kind="Function"}

```manuscript
fn values(data: Bytes) -> List[Int]
```

## with_value {data-api-kind="Function"}

```manuscript
fn with_value(data: Bytes, index: Int, value: Int) -> Bytes
```

