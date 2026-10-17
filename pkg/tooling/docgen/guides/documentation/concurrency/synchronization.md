+++
title = "Synchronizing updates"
weight = 6
+++

# Synchronizing updates

Use synchronized services for application state shared by requests and scheduled work.

## Synchronized

Import `Synchronized` and, when an annotation needs it, `SynchronizedGuard` from `@std/sync.ms`. `Synchronized[T](value: T)` is an opaque reference containing one value and one mutex. Aliases share both. Its only operation is `lock() -> SynchronizedGuard[T]`; waiting for a state change goes through the guard (see [Waiting for a change](#waiting-for-a-change)).

<!-- manuscript-example: {"mode":"test"} -->
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

Reacquiring a lock held by the current operation faults before waiting, including through ordinary helpers and shielded cleanup. A different operation waits, even if its execution ancestor holds the guard. A running child can wait while its parent finishes a critical section, releases the guard, and then joins the child.

Cross-task lock and join cycles are not detected automatically. They remain programming errors; acquire multiple locks in a consistent order and release a held guard before joining or closing work that needs it. Ordinary lock waits observe cancellation and deadlines. A group timeout can stop an ordinary blocked task, but joining still waits for its cleanup. Shielded cleanup ignores the initiating cancellation and expired deadline, so a lock cycle in cleanup can remain blocked indefinitely. The native application host has no cleanup watchdog; cancellation and timeouts do not guarantee escape from every deadlock. See [cancellation and timeouts](cancellation.md) and [shutdown](shutdown.md#limits).

Set replaces the stored value immediately. Faults, propagated errors, and cancellation do not roll back committed writes or external effects. Get returns the stored value, including the same mutable record or collection reference. Use `.clone()` while holding the guard to retain separate outer storage; nested references remain shared. The lock protects access made while held; it does not attach synchronization to every reachable object. A mutable record, collection, or local Queue obtained through get must be used entirely within the guard scope when shared, and all callers must acquire the same wrapper. Put related fields in one record inside one `Synchronized` to update their invariant together.

## Waiting for a change

A guard can wait for another task to change the shared value without polling. `wait()` releases the lock, sleeps until some task calls `notify_all()`, then reacquires the lock before returning; `notify_all()` wakes every task waiting on the same `Synchronized`.

```manuscript
fn wait_until_ready(ready: Synchronized[Bool]) -> Unit:
    with locked = ready.lock():
        while not locked.get():
            locked.wait()

fn mark_ready(ready: Synchronized[Bool]) -> Unit:
    with locked = ready.lock():
        locked.set(value: true)
        locked.notify_all()
```

- Waiting may return without a matching notification, and another task may change the value first. Always re-check the condition in a loop.
- The registration and the lock release are one atomic step, so a notification issued after the caller observed the value cannot be lost.
- Only the operation that acquired a guard may call `wait` or `notify_all` through it. Another task using a captured alias faults, as does a closed guard. While waiting, `get`, `set` through any alias fault because the lock is released.
- The reacquisition after a notification is an ordinary cancellable lock wait.
- Cancellation, a group timeout or a host deadline interrupts `wait` without reacquiring the lock. The guard stays released, the cancellation fault unwinds the `with` scope, and closing the guard does nothing. Cleanup registered inside that scope therefore runs without the lock. Because a cancelled wait never needs the lock, a parent holding it while closing a group of waiters cannot deadlock them.
- Closing a guard alias during `wait` makes `wait` fault when it wakes, instead of reinstating the lock.

The standard [`BlockingQueue`](queues.md#blocking-queue) is a ready-made waiting queue. Build other waiting structures the same way: a `Synchronized` value holding the state, with each operation looping on `wait`.

`Synchronized` replaces the former `State` API. Migrate each get/set/swap sequence to a `with locked = value.lock()` scope; use guard get/set within that scope. There is no implicit transaction, retry callback, mutable-reference syntax, or sharing bound.
