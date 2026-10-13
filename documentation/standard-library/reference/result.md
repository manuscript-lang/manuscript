+++
title = "result"
+++

# @std/result.ms

These names are available in the prelude; no import required.

Explicit imports with `import Name from "@std/result.ms"` remain supported.

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

### Result.error

An expected failure value; it is distinct from faults and cancellation.

```manuscript
case error(cause: E)
```

### Result.ok

A successful result, retaining its payload without a deep copy.

```manuscript
case ok(value: T)
```

### Result.error.cause

The original domain error, retained through compatible Result propagation.

```manuscript
cause: E
```

### Result.ok.value

The successful value returned by unwrap, matching, or propagation.

```manuscript
value: T
```

### Result.and_then[U]

Calls transform only on success. Its result keeps the same error type.

```manuscript
fn and_then[U](transform: fn(value: T) -> Result[U, E]) -> Result[U, E]:
```

### Result.is_error

Reports whether this result contains an expected error.

```manuscript
fn is_error() -> Bool:
```

### Result.is_ok

Reports whether this result contains a successful value.

```manuscript
fn is_ok() -> Bool:
```

### Result.map[U]

Transforms only a successful payload, preserving an error unchanged.

```manuscript
fn map[U](transform: fn(value: T) -> U) -> Result[U, E]:
```

### Result.to_optional

Returns some with the original success payload, or none for an error.

```manuscript
fn to_optional() -> Optional[T]:
```

### Result.unwrap

Returns the successful payload; faults when this is an error.

```manuscript
fn unwrap() -> T:
```

### Result.unwrap_error

Returns the error payload; faults when this is successful.

```manuscript
fn unwrap_error() -> E:
```

### Result.unwrap_or

Returns the successful payload, or the eagerly evaluated fallback.

```manuscript
fn unwrap_or(fallback: T) -> T:
```

### Result.unwrap_or_else

Calls create once with the original error only when this is an error.

```manuscript
fn unwrap_or_else(create: fn(cause: E) -> T) -> T:
```

