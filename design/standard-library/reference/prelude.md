+++
title = "prelude"
+++

# prelude

Intrinsic names; no import required.

## Bool {data-api-kind="Type"}

```manuscript
type Bool
```

## Equal {data-api-kind="Type"}

```manuscript
type Equal
```

## Float {data-api-kind="Type"}

```manuscript
type Float:
    fn to_precision(precision: Int) -> Result[String, LibraryError]
    fn to_exponential(digits: Int) -> Result[String, LibraryError]
    fn to_fixed(digits: Int) -> Result[String, LibraryError]
    fn to_string() -> String
    fn is_nan() -> Bool
    fn is_finite() -> Bool
    fn truncate_to_int() -> Optional[Int]
```

## Hashable {data-api-kind="Type"}

```manuscript
type Hashable
```

## Int {data-api-kind="Type"}

```manuscript
type Int:
    fn to_string(radix: Int) -> String
    fn to_float() -> Float
    fn to_decimal() -> Decimal
```

## Never {data-api-kind="Type"}

```manuscript
type Never
```

## String {data-api-kind="Type"}

```manuscript
type String:
    fn normalize(form: String, max_bytes: Int) -> Result[String, LibraryError]
    fn concat(values: String) -> String
    fn contains(text: String) -> Bool
    fn ends_with(suffix: String) -> Bool
    fn lower() -> String
    fn repeat(count: Int, max_bytes: Int) -> Result[String, LibraryError]
    fn replace(old: String, new: String, max_replacements: Int) -> String
    fn scalar_length() -> Int
    fn scalar_values() -> List[Int]
    fn slice_scalars(start: Int, end: Int) -> Result[String, LibraryError]
    fn split(separator: String, max_parts: Int) -> List[String]
    fn starts_with(prefix: String) -> Bool
    fn trim() -> String
    fn upper() -> String
    fn at(index: Int) -> Optional[String]
    fn scalar_at(index: Int) -> Optional[Int]
    fn index_of(value: String) -> Optional[Int]
    fn last_index_of(value: String) -> Optional[Int]
    fn trim_start() -> String
    fn trim_end() -> String
    fn pad_start(target_length: Int, padding: String, max_bytes: Int) -> Result[String, LibraryError]
    fn pad_end(target_length: Int, padding: String, max_bytes: Int) -> Result[String, LibraryError]
    fn replace_all(old: String, new: String, max_bytes: Int) -> Result[String, LibraryError]
    fn slice(start: Int, end: Int) -> String
    fn substring(start: Int, end: Int) -> String
    fn byte_length() -> Int
    fn to_bytes() -> Bytes
    fn parse_int() -> Optional[Int]
```

## Unit {data-api-kind="Type"}

```manuscript
type Unit
```

