+++
title = "Concurrent access and resource lifetime"
weight = 50
+++

# Concurrent access and resource lifetime

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Every source value is safe to share between concurrent operations. Sharing needs no annotation, compiler bound, or callable proof. It does not keep a resource open or register cleanup.

## Data and services

Records, alternatives, bytes, and collections are immutable. A `var` reassigns a local binding; it does not make a record field mutable. Closures snapshot captured bindings, including a mutable local's current value, and cannot assign to captured outer locals.

Native services and builders synchronize their mutable internals and resource lifecycles. Resource APIs may serialize simultaneous calls or report unsupported overlapping use. Race safety does not make several calls atomic or establish their execution order. Use [Synchronized](../../standard-library/data-and-io/synchronized-state.md#synchronized) when related reads and writes must run under one lock.

Wrappers coordinate the closed-state check, access to the underlying handle, and closure as one lifecycle protocol. A flag check followed by unprotected I/O is insufficient. A stale lease or lock guard must never access a resource or protected value after release.

## Contract views

`Contract(value: receiver)` retains the implementing receiver. There is one contract-view type; it can be passed through fields, parameters, returns, and collections and used concurrently. Generic behavioral bounds require the named operations only. Native adapters must make every exposed receiver safe to share; an unsafe native receiver is not a supported source value.

## Function values

Named functions, closures, bound methods, function fields, and function parameters are ordinary shareable values. Copies, generic forwarding, collection storage, and return values preserve their normal call behavior. Concurrency APIs check the function signature, with no separate capture-sharing eligibility or proof-erasure rules. An operation may return another function.

Capture application services and job data for background work, and acquire job resources inside that work's own `with` scopes. A resource captured beyond its `with` scope remains a valid reference, but subsequent operations report closed state. Sharing, resource lifetime, and work lifetime remain separate guarantees.
