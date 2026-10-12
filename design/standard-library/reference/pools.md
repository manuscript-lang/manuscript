+++
title = "pools"
+++

# @std/pools.ms

Import each required symbol with `import Name from "@std/pools.ms"`.

## Lease {data-api-kind="Interface"}

```manuscript
Lease: Lease[T]
type parameters: T
operation close: fn()->Unit
operation get: fn()->Result[T, PoolError]
```

## Pool {data-api-kind="Interface"}

```manuscript
Pool: Pool[T]
type parameters: T
field resources: List[T]
operation acquire: fn()->Result[Lease[T], PoolError]
operation close: fn()->Unit
```

## PoolError {data-api-kind="Alternative"}

```manuscript
PoolError: PoolError
case Closed
```

