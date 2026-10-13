+++
title = "result"
+++

# @std/result.ms

These names are available in the prelude; no import required.

Explicit imports with `import Name from "@std/result.ms"` remain supported.

## Result {data-api-kind="Alternative"}

```manuscript
type Result[T, U]:
    case ok(value: T)
    case error(cause: U)
```

