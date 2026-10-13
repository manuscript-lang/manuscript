+++
title = "prelude"
+++

# prelude

Names available in every module; no import required.

## Bool {data-api-kind="Type"}

```manuscript
type Bool:
```

## Equal {data-api-kind="Interface"}

Equality and hashing are ordinary operation interfaces. Built-in data retains
its value semantics; an explicit implementation selects domain identity.

```manuscript
interface Equal:
    fn equals(other: Equal) -> Bool
```

## Error {data-api-kind="Interface"}

A contract for expected failures that can provide a human-readable message.

```manuscript
interface Error:
    fn message() -> String
```

## Float {data-api-kind="Type"}

```manuscript
type Float:
    fn to_precision(precision: Int) -> Result[String, NumberError]:
    fn to_exponential(digits: Int) -> Result[String, NumberError]:
    fn to_fixed(digits: Int) -> Result[String, NumberError]:
    fn to_string() -> String:
    fn is_nan() -> Bool:
    fn is_finite() -> Bool:
    fn truncate_to_int() -> Optional[Int]:
```

## Hashable {data-api-kind="Interface"}

A type with a stable hash consistent with its `Equal` implementation.

```manuscript
interface Hashable:
    fn hash() -> Int
```

## Int {data-api-kind="Type"}

```manuscript
type Int:
    fn to_string(radix: Int) -> String:
    fn to_float() -> Float:
    fn to_decimal() -> Decimal:
```

## Never {data-api-kind="Type"}

```manuscript
type Never:
```

## Optional {data-api-kind="Alternative"}

Represents a value that may be absent: `some(value)` or `none`.

```manuscript
type Optional[T]:
    case some(value: T)
    case none
    fn is_some() -> Bool:
    fn is_none() -> Bool:
    fn unwrap() -> T:
    fn unwrap_or(fallback: T) -> T:
    fn unwrap_or_else(create: fn() -> T) -> T:
    fn map[U](transform: fn(value: T) -> U) -> Optional[U]:
    fn and_then[U](transform: fn(value: T) -> Optional[U]) -> Optional[U]:
    fn or_else(create: fn() -> Optional[T]) -> Optional[T]:
    fn ok_or[E](cause: E) -> Result[T, E]:
    fn ok_or_else[E](create: fn() -> E) -> Result[T, E]:
```

## Result {data-api-kind="Alternative"}

Holds either a successful value (`ok`) or an expected failure (`error`).

```manuscript
type Result[T, E]:
    case ok(value: T)
    case error(cause: E)
    fn is_ok() -> Bool:
    fn is_error() -> Bool:
    fn unwrap() -> T:
    fn unwrap_error() -> E:
    fn unwrap_or(fallback: T) -> T:
    fn unwrap_or_else(create: fn(cause: E) -> T) -> T:
    fn map[U](transform: fn(value: T) -> U) -> Result[U, E]:
    fn and_then[U](transform: fn(value: T) -> Result[U, E]) -> Result[U, E]:
    fn to_optional() -> Optional[T]:
```

## String {data-api-kind="Type"}

```manuscript
type String:
    fn normalize(form: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
    fn concat(values: String) -> String:
    fn contains(text: String) -> Bool:
    fn ends_with(suffix: String) -> Bool:
    fn lower() -> String:
    fn repeat(count: Int, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
    fn replace(old: String, new: String, max_replacements: Optional[Int] = none) -> String:
    fn scalar_length() -> Int:
    fn scalar_values() -> List[Int]:
    fn slice_scalars(start: Int, end: Int) -> Result[String, StringError]:
    fn split(separator: String, max_parts: Optional[Int] = none) -> List[String]:
    fn starts_with(prefix: String) -> Bool:
    fn trim() -> String:
    fn upper() -> String:
    fn at(index: Int) -> Optional[String]:
    fn scalar_at(index: Int) -> Optional[Int]:
    fn index_of(value: String) -> Optional[Int]:
    fn last_index_of(value: String) -> Optional[Int]:
    fn trim_start() -> String:
    fn trim_end() -> String:
    fn pad_start(target_length: Int, padding: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
    fn pad_end(target_length: Int, padding: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
    fn replace_all(old: String, new: String, max_bytes: Optional[Int] = none) -> Result[String, StringError]:
    fn slice(start: Int, end: Int) -> String:
    fn substring(start: Int, end: Int) -> String:
    fn byte_length() -> Int:
    fn to_bytes() -> Bytes:
    fn parse_int() -> Optional[Int]:
```

## Unit {data-api-kind="Type"}

```manuscript
type Unit:
```

