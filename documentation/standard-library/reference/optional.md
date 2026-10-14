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
    fn ok_or[E](cause: E) -> Result[T, E]:
    fn ok_or_else[E](create: fn() -> E) -> Result[T, E]:
```

### Optional.none

An absent value with no payload; no T needs to be constructed.

```manuscript
case none
```

### Optional.some

A present payload, retained by reference when T is mutable.

```manuscript
case some(value: T)
```

### Optional.some.value

The contained value; unwrap and matching return this original payload.

```manuscript
value: T
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

Returns true for some(value), and false for none.

```manuscript
fn is_some() -> Bool:
```

### Optional.map[U]

Transforms a present payload; none remains absent.

```manuscript
fn map[U](transform: fn(value: T) -> U) -> Optional[U]:
```

### Optional.ok_or[E]

Returns ok with the original payload, or error with the eager cause.

```manuscript
fn ok_or[E](cause: E) -> Result[T, E]:
```

### Optional.ok_or_else[E]

Constructs an error once only for none; present payloads remain unchanged.

```manuscript
fn ok_or_else[E](create: fn() -> E) -> Result[T, E]:
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

