+++
title = "result"
+++

# @std/result.ms

Import each required symbol with `import Name from "@std/result.ms"`.

## Result {data-api-kind="Alternative"}

```manuscript
Result: Result[T, U]
type parameters: T, U
case ok(value: T)
case error(cause: U)
```

## map_error {data-api-kind="Function"}

```manuscript
map_error: fn(result: Result[T, E], transform: fn(cause: E)->F)->Result[T, F]
type parameters: T, E, F
```

