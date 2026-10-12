+++
title = "pools"
+++

# @std/pools.ms

Import each required symbol with `import Name from "@std/pools.ms"`.

## Lease

Kind: native.

```text
Lease: Lease[T]
type parameters: T: Shareable
operation close: fn()->Unit
operation get: fn()->Result[T, PoolError]
```

## Pool

Kind: native.

```text
Pool: Pool[T]
type parameters: T: Shareable
field resources: List[T]
operation acquire: fn()->Result[Lease[T], PoolError]
operation close: fn()->Unit
```

## PoolError

Kind: alternative.

```text
PoolError: PoolError
case Closed
```

