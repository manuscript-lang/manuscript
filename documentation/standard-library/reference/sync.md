+++
title = "sync"
+++

# @std/sync.ms

Import each required symbol with `import Name from "@std/sync.ms"`.

## Synchronized {data-api-kind="Native type"}

Protects a value shared across tasks. Lock before reading or updating the value.

```manuscript
type Synchronized[T]:
    value: T
    fn lock() -> SynchronizedGuard[T]:
```

### Synchronized.value

Initial constructor payload; retain its mutable aliases only with the same guarded access policy.

```manuscript
value: T
```

### Synchronized.lock

Waits for an exclusive guard; caller cancellation interrupts a pending acquisition.
Keep the guard in a with scope so every exit releases it.

```manuscript
fn lock() -> SynchronizedGuard[T]:
```

## SynchronizedGuard {data-api-kind="Native type"}

Holds a synchronization lock. Closing the guard releases the lock.

```manuscript
type SynchronizedGuard[T]:
    fn get() -> T:
    fn set(value: T) -> Unit:
    fn close() -> Unit:
```

### SynchronizedGuard.close

Releases the lock for every alias of this guard; repeated close does nothing.

```manuscript
fn close() -> Unit:
```

### SynchronizedGuard.get

Returns the original guarded payload, without cloning; a closed guard faults.

```manuscript
fn get() -> T:
```

### SynchronizedGuard.set

Replaces the guarded payload without copying it; a closed guard faults.

```manuscript
fn set(value: T) -> Unit:
```

