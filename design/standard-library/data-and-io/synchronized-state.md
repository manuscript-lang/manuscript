+++
title = "Synchronized state, pools, and leases"
weight = 42
+++

# Synchronized state, pools, and leases

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Shared application state and pools are synchronized services. A pool lease is an ordinary resource object registered with `with` and returned to the pool by `close()`.

Pool references can be shared by requests and background work. A job acquires its own lease under its own scope. Retaining a lease reference does not prolong its lease lifetime.

Access and closure must be coordinated: close waits for or cancels outstanding operations before allowing reuse, and stale aliases report closed state rather than using a connection assigned to another caller. Supported simultaneous use is explicit in the adapter/service contract.

## State

Import `State` from `@std/state.ms`. `State[T: Shareable](value: T)` is an opaque synchronized reference. `get() -> T`, `set(value: T) -> Unit`, and `swap(value: T) -> T` each execute atomically. Swap returns the previous value. A read followed by a write is not an atomic update. State is shareable but has no equality, hashing, or cleanup operation. Each operation checks caller cancellation before and after its transition; committed changes are not rolled back.

## Pools and leases

Import `Pool`, `Lease`, and `PoolError` from `@std/pools.ms`. `Pool[T](resources: List[T])` owns a nonempty fixed collection of distinct resource receivers. `T` must be a concrete shared operation-contract view declaring `close() -> Unit`. Construct views explicitly before pooling; a type variable's implementation bound does not establish this representation at construction. The supplied resources must remain under the pool's exclusive lifecycle management.

```text
# Pool[T]
fn acquire() -> Result[Lease[T], PoolError]
fn close() -> Unit

# Lease[T]
fn get() -> Result[T, PoolError]
fn close() -> Unit
```

Acquire waits cancellably for capacity. Closed admission returns `PoolError.Closed`. Delivery that loses to cancellation releases its lease before unwind. Pool and lease objects are shareable, opaque, and eligible for `with`; they have no equality or hashing.

Get returns a guarded contract view. Calls through that view admit under the lease's lifetime, including method values saved before release. Closing the view releases the lease. Lease close stops admission, cancels and joins admitted operations, and returns capacity exactly once; concurrent closers join the same release. A later get returns `Closed`. Stale I/O views return `IoError.Closed`; stale operations without an I/O error result fault. Release during an admitted operation interrupts it; I/O reports `Closed`, and other contracts report a programming fault unless caller cancellation already applies.

Pool close stops acquisition, wakes waiters, invalidates every lease, joins its operations, then closes owned receivers in reverse supplied order. It is idempotent; concurrent callers observe the same release fault. A lease or pool cannot join its own active operation. Closing may wait indefinitely for uncooperative native code; shutdown escalation is separate.

See [sharing](../../ownership-and-cleanup/values/sharing.md), [release](../../ownership-and-cleanup/cleanup/resource-release.md), and [background resources](../tasks/background.md).
