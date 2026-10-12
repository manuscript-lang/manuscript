+++
title = "result"
+++

# @std/result.ms

Import each required symbol with `import Name from "@std/result.ms"`.

## Result {data-api-kind="Alternative"}

```manuscript
type Result[T, U]:
    case ok(value: T)
    case error(cause: U)
```

