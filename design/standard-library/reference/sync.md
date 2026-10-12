+++
title = "sync"
+++

# @std/sync.ms

Import each required symbol with `import Name from "@std/sync.ms"`.

## Synchronized {data-api-kind="Native type"}

```manuscript
type Synchronized[T]:
    value: T
    fn lock() -> SynchronizedGuard[T]
```

## SynchronizedGuard {data-api-kind="Native type"}

```manuscript
type SynchronizedGuard[T]:
    fn get() -> T
    fn set(value: T) -> Unit
    fn close() -> Unit
```

