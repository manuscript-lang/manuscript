+++
title = "Synchronizing updates"
weight = 6
+++

# Synchronizing updates

Use synchronized services for application state shared by requests and scheduled work.

## Synchronized

Import `Synchronized` and, when an annotation needs it, `SynchronizedGuard` from `@std/sync.ms`. `Synchronized[T](value: T)` is an opaque reference containing one value and one mutex. Aliases share both. Its only operation is `lock() -> SynchronizedGuard[T]`.

```manuscript
import panic from "@std/faults.ms"
import Synchronized from "@std/sync.ms"

test "a complete update holds one lock":
    let counter = Synchronized(0)
    with locked = counter.lock():
        locked.set(value: locked.get() + 1)
    with locked = counter.lock():
        if not (locked.get() == 1):
            return panic(message: "check failed")
```

`lock()` waits cancellably for exclusive admission. The guard exposes `get() -> T`, `set(value: T) -> Unit`, and `close() -> Unit`; it has no source constructor and implements `Closeable`. Use `with` to release it on normal exit, return, loop exits, propagated errors, faults, and cancellation. The synchronized container itself has no close operation. Neither type has equality or hashing.

The lock remains held across ordinary calls and suspension until the guard closes. Cancellation never forcibly releases an executing critical section: the holder unwinds and performs shielded cleanup first. An acquisition that loses to cancellation before delivery releases the undelivered guard. There is no FIFO or starvation-freedom guarantee.

Guard aliases and saved methods use the same active acquisition. Get/set and release coordinate atomically; after release, get/set fault through every alias, even after another task acquires the container. Close is idempotent and cannot release a later acquisition. A guard may pass through helpers or be captured by concurrent work. Calls through the same guard are individually safe, but sharing it does not serialize complete sequences between those callers; acquire separately for independent critical sections.

Reacquiring a lock held by the current operation faults before waiting, including through ordinary helpers and shielded cleanup. A running child may wait for an ancestor's lock while that ancestor continues its critical section and releases the guard before joining.

If a lock-holding ancestor joins or closes work that depends on the lock waiter, the waiter faults. This applies whether the child attempts acquisition before or after the ancestor starts waiting, including nested groups, failed-task joins that wait for sibling cleanup, and service shutdown. The child task reports `ExecutionError.Crashed` through its join boundary; the ancestor's join does not itself fault merely for creating this cycle. Cancelled ordinary waits stop participating in the cycle check, but shielded cleanup still waits and can fault. Cancellation never forcibly releases an executing holder.

The cycle check uses the guard's acquisition lifetime. It remains conservative when another operation could close a guard alias: a detected cycle still faults even if that independent release could eventually let it finish. It does not prove a permanent deadlock, detect arbitrary I/O dependencies, or guarantee detection of independent-lock or cross-service cycles. Those remain programming errors; acquire multiple locks in a consistent order. Keep critical sections short and avoid joining work that needs a held lock.

An ancestor-cycle fault in shielded task cleanup remains a programming fault; if the group's parent is cancelled, group closure reports an unobserved fault as `TaskGroup fault during cancellation`.

Set replaces the stored value immediately. Faults, propagated errors, and cancellation do not roll back committed writes or external effects. Get returns the stored value, including the same mutable record or collection reference. Use `.clone()` while holding the guard to retain separate outer storage; nested references remain shared. The lock protects access made while held; it does not attach synchronization to every reachable object. A mutable record, collection, or local Queue obtained through get must be used entirely within the guard scope when shared, and all callers must acquire the same wrapper. Put related fields in one record inside one `Synchronized` to update their invariant together.

`Synchronized` replaces the former `State` API. Migrate each get/set/swap sequence to a `with locked = value.lock()` scope; use guard get/set within that scope. There is no implicit transaction, retry callback, mutable-reference syntax, or sharing bound.
