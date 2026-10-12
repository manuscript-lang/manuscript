+++
title = "pools"
+++

# @std/pools.ms

Import each required symbol with `import Name from "@std/pools.ms"`.

## Lease

Kind: interface.

```manuscript
Lease: Lease[T]
type parameters: T
operation close: fn()->Unit
operation get: fn()->Result[T, PoolError]
```

## Pool

Kind: interface.

```manuscript
Pool: Pool[T]
type parameters: T
field resources: List[T]
operation acquire: fn()->Result[Lease[T], PoolError]
operation close: fn()->Unit
```

## PoolError

Kind: alternative.

```manuscript
PoolError: PoolError
case Closed
```

