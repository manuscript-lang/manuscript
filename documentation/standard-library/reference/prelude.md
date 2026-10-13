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

## List {data-api-kind="Native type"}

An ordered collection of values with indexing, iteration, and transformation operations.

```manuscript
type List[T]:
    fn clone() -> List[T]:
    fn at(index: Int) -> Optional[T]:
    fn contains(value: T) -> Bool:
    fn index_of(value: T) -> Optional[Int]:
    fn last_index_of(value: T) -> Optional[Int]:
    fn first() -> Optional[T]:
    fn last() -> Optional[T]:
    fn is_empty() -> Bool:
    fn prepend(value: T) -> List[T]:
    fn set(index: Int, value: T) -> List[T]:
    fn remove(index: Int) -> List[T]:
    fn with_value(index: Int, value: T) -> List[T]:
    fn without(index: Int) -> List[T]:
    fn slice(start: Int, end: Int) -> List[T]:
    fn reverse_in_place() -> List[T]:
    fn reversed() -> List[T]:
    fn reverse() -> List[T]:
    fn sorted(compare: fn(left: T, right: T) -> Int) -> List[T]:
    fn filter(predicate: fn(value: T) -> Bool) -> List[T]:
    fn find(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_last(predicate: fn(value: T) -> Bool) -> Optional[T]:
    fn find_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    fn find_last_index(predicate: fn(value: T) -> Bool) -> Optional[Int]:
    fn some(predicate: fn(value: T) -> Bool) -> Bool:
    fn every(predicate: fn(value: T) -> Bool) -> Bool:
    fn for_each(operation: fn(value: T) -> Unit) -> Unit:
    fn group_by[K: Hashable](key: fn(value: T) -> K) -> Map[K, List[T]]:
    fn map[U](transform: fn(value: T) -> U) -> List[U]:
    fn flat_map[U](transform: fn(value: T) -> List[U]) -> List[U]:
    fn fold[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn fold_right[A](initial: A, step: fn(accumulator: A, value: T) -> A) -> A:
    fn with_values(start: Int, delete_count: Int, replacement: List[T]) -> List[T]:
    fn fill(value: T, start: Int, end: Int) -> List[T]:
    fn copy_within(target: Int, start: Int, end: Int) -> List[T]:
    fn to_set() -> Set[T]:
    fn keys() -> List[Int]:
    fn entries() -> List[ListEntry[T]]:
    fn join(separator: String) -> String:
    fn append(value: T) -> List[T]:
    fn concat(values: List[T]) -> List[T]:
    fn length() -> Int:
```

## Map {data-api-kind="Native type"}

A mutable key-value collection. Keys use explicit `Hashable` value semantics.

```manuscript
type Map[T: Hashable, U]:
    fn clone() -> Map[T, U]:
    fn is_empty() -> Bool:
    fn filter(predicate: fn(key: T, value: U) -> Bool) -> Map[T, U]:
    fn get_or(key: T, fallback: U) -> U:
    fn fold[A](initial: A, step: fn(accumulator: A, key: T, value: U) -> A) -> A:
    fn find(predicate: fn(key: T, value: U) -> Bool) -> Optional[MapEntry[T, U]]:
    fn some(predicate: fn(key: T, value: U) -> Bool) -> Bool:
    fn every(predicate: fn(key: T, value: U) -> Bool) -> Bool:
    fn with_default(key: T, value: U) -> Map[T, U]:
    fn with_default_from(key: T, create: fn(key: T) -> U) -> Map[T, U]:
    fn clear() -> Map[T, U]:
    fn keys() -> List[T]:
    fn values() -> List[U]:
    fn entries() -> List[MapEntry[T, U]]:
    fn merge(other: Map[T, U]) -> Map[T, U]:
    fn for_each(operation: fn(key: T, value: U) -> Unit) -> Unit:
    fn contains(key: T) -> Bool:
    fn get(key: T) -> Optional[U]:
    fn length() -> Int:
    fn add(key: T, value: U) -> Map[T, U]:
    fn with_entry(key: T, value: U) -> Map[T, U]:
    fn without(key: T) -> Map[T, U]:
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
    fn replace_first(old: String, new: String, max_replacements: Optional[Int] = none) -> String:
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

