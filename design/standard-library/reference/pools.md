+++
title = "pools"
+++

# @std/pools.ms

Import each required symbol with `import Name from "@std/pools.ms"`.

## Lease {data-api-kind="Native type"}

```manuscript
type Lease[T]:
    fn close() -> Unit
    fn get() -> Result[T, PoolError]
```

## Pool {data-api-kind="Native type"}

```manuscript
type Pool[T]:
    resources: List[T]
    fn acquire() -> Result[Lease[T], PoolError]
    fn close() -> Unit
```

## PoolError {data-api-kind="Alternative"}

```manuscript
type PoolError:
    case Closed
```

