+++
title = "Sharing data"
weight = 5
+++

# Sharing data

Every source value may be passed between concurrent operations. Passing a reference does not synchronize access to the referenced object. Sharing needs no annotation, compiler bound, or callable proof. It does not keep a resource open or register cleanup.

## Data and services

Records and collections are mutable. Alternative tags, strings, and bytes retain their value behavior. `let` fixes a binding, while `var` permits reassignment; neither freezes a referenced record or collection. Closures snapshot captured bindings, including a mutable local's current value, and cannot assign to captured outer locals.

Native services and builders synchronize their mutable internals and resource lifecycles. Resource APIs may serialize simultaneous calls or report unsupported overlapping use. Race safety does not make several calls atomic or establish their execution order. Use [Synchronized](synchronization.md#synchronized) when related reads and writes must run under one lock.

Wrappers coordinate the closed-state check, access to the underlying handle, and closure as one lifecycle protocol. A flag check followed by unprotected I/O is insufficient. A stale lock guard must never access a resource or protected value after release.

A [Queue](queues.md) is a local mutable collection with no internal synchronization. When shared, keep it in one `Synchronized[Queue[T]]` and hold a separately acquired guard for each caller's full use, including reads. Queue aliases and bound methods must follow that same discipline; the compiler does not track or enforce lock ownership. Records may contain queue references. A shallow record clone retains the same queue reference.

## Captured mutable data

A closure snapshots the reference to a Map, List, or record, not its contents. Two tasks that capture the same object share its storage. Unsynchronized writes can lose updates or race with reads; `let` does not prevent this. Read-only sharing is safe only while no caller mutates the shared object.

This fragment is unsafe when callbacks or other users access `counts` concurrently:

```manuscript
let counts = {"hits": 0}
let task = tasks.start(fn():
    counts.with_entry(key: "hits", value: counts.get("hits").unwrap_or(0) + 1)
)
```

Store the object in `Synchronized` and acquire a fresh guard inside each callback. Keep the entire read-modify-write under that guard. This replacement fragment requires `Synchronized` from `@std/sync.ms`:

```manuscript
let counts = Synchronized({"hits": 0})
let task = tasks.start(fn():
    with locked = counts.lock():
        let values = locked.get()
        values.with_entry(key: "hits", value: values.get("hits").unwrap_or(0) + 1)
)
```

Every reader and writer must use the same wrapper. Do not retain and use an unguarded alias to the original object. See [synchronization](synchronization.md) for guard lifetimes and shallow copies.

`ms lint` reports advisory **MSL105** for direct mutations of captured standard collections and direct captured record-field assignments inside inline callbacks supplied to `TaskGroup.start`, `Scheduler.start`, `Scheduler.after`, `Scheduler.every`, `Network.serve`, and `Network.serve_stream`. It uses checked bindings and method identities, so read-only captures, callback-local values, and unrelated methods named `start` do not trigger it. Access through a guard acquired inside the callback follows the pattern above.

The advisory does not prove that a race occurs or that a program without findings is race-free. It does not follow aliases, named callbacks, stored function values, helper calls, nested field paths, or mutations inside other nested closures. It does not verify that guards protect every alias or that returned mutable values remain within the guard scope. Sharing stays freely permitted; review ownership and synchronization even when lint is silent.

## Contract views

`Contract(value: receiver)` retains the implementing receiver. There is one contract-view type; it can be passed through fields, parameters, returns, and collections and used according to its receiver's concurrency contract. Generic behavioral bounds require the named operations only. Native service adapters synchronize their receivers and resource lifecycles. A source implementation that holds a local queue must use a synchronized wrapper before exposing concurrent operations.

## Function values

Named functions, closures, bound methods, function fields, and function parameters are ordinary values. Copies, generic forwarding, collection storage, and return values preserve their normal call behavior. Concurrency APIs check the function signature, with no separate capture-sharing eligibility or proof-erasure rules. An operation may return another function.

Capture application services and job data for scheduled work, and acquire job resources inside that work's own `with` scopes. A resource captured beyond its `with` scope remains a valid reference, but subsequent operations report closed state. Sharing, resource lifetime, and work lifetime remain separate guarantees.
