# Canonical standard-library declarations. Implementations are native.

# Protects a value shared across tasks. Lock before reading or updating the value.
export type Synchronized[T]:
    # Initial constructor payload; retain its mutable aliases only with the same guarded access policy.
    value: T
    # Waits for an exclusive guard; caller cancellation interrupts a pending acquisition.
    # Keep the guard in a with scope so every exit releases it.
    fn lock() -> SynchronizedGuard[T]:

# Holds a synchronization lock. Closing the guard releases the lock.
export type SynchronizedGuard[T]:
    # Returns the original guarded payload, without cloning; a closed guard faults.
    fn get() -> T:
    # Replaces the guarded payload without copying it; a closed guard faults.
    fn set(value: T) -> Unit:
    # Releases the lock for every alias of this guard; repeated close does nothing.
    fn close() -> Unit:

# documentation documentation/concurrency/sharing.md
# +++
# title = "Sharing data"
# weight = 5
# +++
#
# # Sharing data
#
# Every source value may be passed between concurrent operations. Passing a reference does not synchronize access to the referenced object. Sharing needs no annotation, compiler bound, or callable proof. It does not keep a resource open or register cleanup.
#
# ## Data and services
#
# Records and collections are mutable. Alternative tags, strings, and bytes retain their value behavior. `let` fixes a binding, while `var` permits reassignment; neither freezes a referenced record or collection. Closures snapshot captured bindings, including a mutable local's current value, and cannot assign to captured outer locals.
#
# Native services and builders synchronize their mutable internals and resource lifecycles. Resource APIs may serialize simultaneous calls or report unsupported overlapping use. Race safety does not make several calls atomic or establish their execution order. Use [Synchronized](synchronization.md#synchronized) when related reads and writes must run under one lock.
#
# Wrappers coordinate the closed-state check, access to the underlying handle, and closure as one lifecycle protocol. A flag check followed by unprotected I/O is insufficient. A stale lock guard must never access a resource or protected value after release.
#
# A [Queue](queues.md) is a local mutable collection with no internal synchronization. When shared, keep it in one `Synchronized[Queue[T]]` and hold a separately acquired guard for each caller's full use, including reads. Queue aliases and bound methods must follow that same discipline; the compiler does not track or enforce lock ownership. Records may contain queue references. A shallow record clone retains the same queue reference.
#
# ## Captured mutable data
#
# A closure snapshots the reference to a Map, List, or record, not its contents. Two tasks that capture the same object share its storage. Unsynchronized writes can lose updates or race with reads; `let` does not prevent this. Read-only sharing is safe only while no caller mutates the shared object. Mutable collections have a stricter access contract: use `Synchronized` for concurrent reads and traversals too, as described in [collection mutation and copies](../core-language/types/collections.md#mutation-and-copies).
#
# This fragment is unsafe when callbacks or other users access `counts` concurrently:
#
# ```manuscript
# let counts = {"hits": 0}
# let task = tasks.start(fn():
#     counts.add(key: "hits", value: counts.get("hits").unwrap_or(0) + 1)
# )
# ```
#
# Store the object in `Synchronized` and acquire a fresh guard inside each callback. Keep the entire read-modify-write under that guard. This replacement fragment requires `Synchronized` from `@std/sync.ms`:
#
# ```manuscript
# let counts = Synchronized({"hits": 0})
# let task = tasks.start(fn():
#     with locked = counts.lock():
#         let values = locked.get()
#         values.add(key: "hits", value: values.get("hits").unwrap_or(0) + 1)
# )
# ```
#
# Every reader and writer must use the same wrapper. Do not retain and use an unguarded alias to the original object. See [synchronization](synchronization.md) for guard lifetimes and shallow copies.
#
# `ms lint` reports advisory **MSL105** for direct mutations of captured standard collections and direct captured record-field assignments inside inline callbacks supplied to `TaskGroup.start`, `Scheduler.start`, `Scheduler.after`, `Scheduler.every`, `Network.serve`, and `Network.serve_stream`. It uses checked bindings and method identities, so read-only captures, callback-local values, and unrelated methods named `start` do not trigger it. Access through a guard acquired inside the callback follows the pattern above.
#
# The advisory does not prove that a race occurs or that a program without findings is race-free. It does not follow aliases, named callbacks, stored function values, helper calls, nested field paths, or mutations inside other nested closures. It does not verify that guards protect every alias or that returned mutable values remain within the guard scope. Sharing stays freely permitted; review ownership and synchronization even when lint is silent.
#
# ## Contract views
#
# `Contract(value: receiver)` retains the implementing receiver. There is one contract-view type; it can be passed through fields, parameters, returns, and collections and used according to its receiver's concurrency contract. Generic behavioral bounds require the named operations only. Native service adapters synchronize their receivers and resource lifecycles. A source implementation that holds a local queue must use a synchronized wrapper before exposing concurrent operations.
#
# ## Function values
#
# Named functions, closures, bound methods, function fields, and function parameters are ordinary values. Copies, generic forwarding, collection storage, and return values preserve their normal call behavior. Concurrency APIs check the function signature, with no separate capture-sharing eligibility or proof-erasure rules. An operation may return another function.
#
# Capture application services and job data for scheduled work, and acquire job resources inside that work's own `with` scopes. A resource captured beyond its `with` scope remains a valid reference, but subsequent operations report closed state. Sharing, resource lifetime, and work lifetime remain separate guarantees.
# end-documentation

# documentation documentation/concurrency/synchronization.md
# +++
# title = "Synchronizing updates"
# weight = 6
# +++
#
# # Synchronizing updates
#
# Use synchronized services for application state shared by requests and scheduled work.
#
# ## Synchronized
#
# Import `Synchronized` and, when an annotation needs it, `SynchronizedGuard` from `@std/sync.ms`. `Synchronized[T](value: T)` is an opaque reference containing one value and one mutex. Aliases share both. Its only operation is `lock() -> SynchronizedGuard[T]`.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import panic from "@std/faults.ms"
# import Synchronized from "@std/sync.ms"
#
# test "a complete update holds one lock":
#     let counter = Synchronized(0)
#     with locked = counter.lock():
#         locked.set(value: locked.get() + 1)
#     with locked = counter.lock():
#         if not (locked.get() == 1):
#             return panic(message: "check failed")
# ```
#
# `lock()` waits cancellably for exclusive admission. The guard exposes `get() -> T`, `set(value: T) -> Unit`, and `close() -> Unit`; it has no source constructor and implements `Closeable`. Use `with` to release it on normal exit, return, loop exits, propagated errors, faults, and cancellation. The synchronized container itself has no close operation. Neither type has equality or hashing.
#
# The lock remains held across ordinary calls and suspension until the guard closes. Cancellation never forcibly releases an executing critical section: the holder unwinds and performs shielded cleanup first. An acquisition that loses to cancellation before delivery releases the undelivered guard. There is no FIFO or starvation-freedom guarantee.
#
# Guard aliases and saved methods use the same active acquisition. Get/set and release coordinate atomically; after release, get/set fault through every alias, even after another task acquires the container. Close is idempotent and cannot release a later acquisition. A guard may pass through helpers or be captured by concurrent work. Calls through the same guard are individually safe, but sharing it does not serialize complete sequences between those callers; acquire separately for independent critical sections.
#
# Reacquiring a lock held by the current operation faults before waiting, including through ordinary helpers and shielded cleanup. A different operation waits, even if its execution ancestor holds the guard. A running child can wait while its parent finishes a critical section, releases the guard, and then joins the child.
#
# Cross-task lock and join cycles are not detected automatically. They remain programming errors; acquire multiple locks in a consistent order and release a held guard before joining or closing work that needs it. Ordinary lock waits observe cancellation and deadlines. A group timeout can stop an ordinary blocked task, but joining still waits for its cleanup. Shielded cleanup ignores the initiating cancellation and expired deadline, so a lock cycle in cleanup can remain blocked indefinitely. The native application host has no cleanup watchdog; cancellation and timeouts do not guarantee escape from every deadlock. See [cancellation and timeouts](cancellation.md) and [shutdown](shutdown.md#limits).
#
# Set replaces the stored value immediately. Faults, propagated errors, and cancellation do not roll back committed writes or external effects. Get returns the stored value, including the same mutable record or collection reference. Use `.clone()` while holding the guard to retain separate outer storage; nested references remain shared. The lock protects access made while held; it does not attach synchronization to every reachable object. A mutable record, collection, or local Queue obtained through get must be used entirely within the guard scope when shared, and all callers must acquire the same wrapper. Put related fields in one record inside one `Synchronized` to update their invariant together.
#
# `Synchronized` replaces the former `State` API. Migrate each get/set/swap sequence to a `with locked = value.lock()` scope; use guard get/set within that scope. There is no implicit transaction, retry callback, mutable-reference syntax, or sharing bound.
# end-documentation
