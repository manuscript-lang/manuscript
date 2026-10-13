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

