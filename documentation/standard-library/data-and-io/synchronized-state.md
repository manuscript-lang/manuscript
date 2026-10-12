+++
title = "Synchronized values, pools, and leases"
weight = 42
+++

# Synchronized values, pools, and leases

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use synchronized services for application state shared by requests and background work. A pool supplies leases: acquire a lease in a `with` block, then return it to the pool through close. Keeping a reference to the lease does not extend its lifetime.

Pool references can be shared by requests and background work. A job acquires its own lease under its own scope. Retaining a lease reference does not prolong its lease lifetime.

Access and closure must be coordinated: close waits for or cancels outstanding operations before allowing reuse, and stale aliases report closed state rather than using a connection assigned to another caller. Supported simultaneous use is explicit in the adapter/service contract.

## Synchronized

Import `Synchronized` and, when an annotation needs it, `SynchronizedGuard` from `@std/sync.ms`. `Synchronized[T](value: T)` is an opaque reference containing one value and one mutex. Aliases share both. Its only operation is `lock() -> SynchronizedGuard[T]`.

```manuscript
import panic from "@std/faults.ms"
import Synchronized from "@std/sync.ms"

test "a complete update holds one lock":
    let counter = Synchronized(value: 0)
    with locked = counter.lock():
        locked.set(value: locked.get() + 1)
    with locked = counter.lock():
        if not (locked.get() == 1):
            return panic(message: "check failed")
```

`lock()` waits cancellably for exclusive admission. The guard exposes `get() -> T`, `set(value: T) -> Unit`, and `close() -> Unit`; it has no source constructor and implements `Closeable`. Use `with` to release it on normal exit, return, loop exits, propagated errors, faults, and cancellation. The synchronized container itself has no close operation. Neither type has equality or hashing.

The lock remains held across ordinary calls and suspension until the guard closes. Cancellation never forcibly releases an executing critical section: the holder unwinds and performs shielded cleanup first. An acquisition that loses to cancellation before delivery releases the undelivered guard. There is no FIFO or starvation-freedom guarantee.

Guard aliases and saved methods use the same active acquisition. Get/set and release coordinate atomically; after release, get/set fault through every alias, even after another task acquires the container. Close is idempotent and cannot release a later acquisition. A guard may pass through helpers or be captured by concurrent work. Calls through the same guard are individually safe, but sharing it does not serialize complete sequences between those callers; acquire separately for independent critical sections.

Reacquiring a lock held by the current operation or an execution ancestor faults before waiting, including from a nested joined task and shielded cleanup. Cycles between independent operations or different locks remain a programming error; acquire multiple locks in a consistent order. Keep critical sections short and avoid waiting for work that needs a held lock.

Set replaces the stored value immediately. Faults, propagated errors, and cancellation do not roll back committed writes or external effects. Get returns the stored value, including the same mutable record or collection reference. Use `.clone()` while holding the guard to retain separate outer storage; nested references remain shared. The lock protects access made while held; it does not attach synchronization to every reachable object. A mutable record, collection, or local Queue obtained through get must be used entirely within the guard scope when shared, and all callers must acquire the same wrapper. Put related fields in one record inside one `Synchronized` to update their invariant together.

`Synchronized` replaces the former `State` API. Migrate each get/set/swap sequence to a `with locked = value.lock()` scope; use guard get/set within that scope. There is no implicit transaction, retry callback, mutable-reference syntax, or sharing bound.

## Pools and leases

Import `Pool`, `Lease`, and `PoolError` from `@std/pools.ms`. `Pool[T](resources: List[T])` owns a nonempty fixed collection of distinct resource receivers. `T` must be a concrete operation-contract view declaring `close() -> Unit`. Construct views explicitly before pooling; a type variable's implementation bound does not establish this representation at construction. The supplied resources must remain under the pool's exclusive lifecycle management.

```manuscript
# Pool[T]
fn acquire() -> Result[Lease[T], PoolError]
fn close() -> Unit

# Lease[T]
fn get() -> Result[T, PoolError]
fn close() -> Unit
```

Acquire waits cancellably for capacity. Closed admission returns `PoolError.Closed`. Delivery that loses to cancellation releases its lease before unwind. Pool and lease objects are opaque, and eligible for `with`; they have no equality or hashing.

Get returns a guarded contract view. Calls through that view admit under the lease's lifetime, including method values saved before release. Closing the view releases the lease. Lease close stops admission, cancels and joins admitted operations, and returns capacity exactly once; concurrent closers join the same release. A later get returns `Closed`. Stale I/O views return `IoError.Closed`; stale operations without an I/O error result fault. Release during an admitted operation interrupts it; I/O reports `Closed`, and other contracts report a programming fault unless caller cancellation already applies.

Pool close stops acquisition, wakes waiters, invalidates every lease, joins its operations, then closes owned receivers in reverse supplied order. It is idempotent; concurrent callers observe the same release fault. A lease or pool cannot join its own active operation. Closing may wait indefinitely for uncooperative native code; shutdown escalation is separate.

See [sharing](../../ownership-and-cleanup/values/sharing.md), [release](../../ownership-and-cleanup/cleanup/resource-release.md), and [background resources](../tasks/background.md).
