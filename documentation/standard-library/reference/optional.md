+++
title = "optional"
+++

# @std/optional.ms

These names are available in the prelude; no import required.

Explicit imports with `import Name from "@std/optional.ms"` remain supported.

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
```

### Optional.and_then[U]

Calls transform only when present, returning its Optional unchanged.

```manuscript
fn and_then[U](transform: fn(value: T) -> Optional[U]) -> Optional[U]:
```

### Optional.is_none

Reports whether this value is absent.

```manuscript
fn is_none() -> Bool:
```

### Optional.is_some

Reports whether this value contains a payload.

```manuscript
fn is_some() -> Bool:
```

### Optional.map[U]

Transforms a present payload; none remains absent.

```manuscript
fn map[U](transform: fn(value: T) -> U) -> Optional[U]:
```

### Optional.or_else

Calls create once only when absent, returning its Optional unchanged.

```manuscript
fn or_else(create: fn() -> Optional[T]) -> Optional[T]:
```

### Optional.unwrap

Returns the payload. Calling this on `none` raises a fault.

```manuscript
fn unwrap() -> T:
```

### Optional.unwrap_or

Returns the contained value, or `fallback` when this is `none`.

```manuscript
fn unwrap_or(fallback: T) -> T:
```

### Optional.unwrap_or_else

Computes a fallback only when this is `none`.

```manuscript
fn unwrap_or_else(create: fn() -> T) -> T:
```

