+++
title = "optional"
+++

# @std/optional.ms

Import each required symbol with `import Name from "@std/optional.ms"`.

## Optional {data-api-kind="Alternative"}

```manuscript
type Optional[T]:
    case some(value: T)
    case none
    fn is_some() -> Bool:
    fn is_none() -> Bool:
    fn unwrap() -> T:
    fn unwrap_or(fallback: T) -> T:
    fn unwrap_or_else(create: fn() -> T) -> T:
```

