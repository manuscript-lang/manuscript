+++
title = "sync"
+++

# @std/sync.ms

Import each required symbol with `import Name from "@std/sync.ms"`.

## Synchronized

Kind: interface.

```text
Synchronized: Synchronized[T]
type parameters: T
field value: T
operation lock: fn()->SynchronizedGuard[T]
```

## SynchronizedGuard

Kind: interface.

```text
SynchronizedGuard: SynchronizedGuard[T]
type parameters: T
operation close: fn()->Unit
operation get: fn()->T
operation set: fn(value: T)->Unit
```

