+++
title = "Resource lifetimes and cleanup"
linkTitle = "Resources & cleanup"
weight = 47
+++

# Resource lifetimes and cleanup

[Design index](../_index.md)

Use `with` when a file, connection, or other resource must close at the end of a block. The runtime reclaims unused memory, but you must arrange release of external resources. Keeping another reference to a resource does not keep it open.

## Reading order

### 1. References and sharing

- [Ordinary references](values/references.md) — Understand what another reference does, and why it does not keep a resource open.
- [Concurrent access and resource lifetime](values/sharing.md) — Check whether data or a function can safely be used by concurrent operations.
- [Aggregates and local construction](values/aggregates.md) — Store resources inside records or collections without assuming automatic cleanup.
- [Assignment and branches](values/control-flow.md) — See what reassignment and branches do to references and registered cleanup.

### 2. Scoped cleanup

- [With scopes](cleanup/scopes.md) — Acquire a resource and close it at the end of a block with `with`.
- [The Closeable contract](cleanup/closeable.md) — Implement the cleanup operation required by `with`.
- [Scope-exit ordering](cleanup/exit-order.md) — Follow cleanup order after a return, error, fault, or cancellation.
- [Shielding and cleanup faults](cleanup/cleanup-faults.md) — Understand cleanup after cancellation and what happens if close itself faults.
- [External resource release](cleanup/resource-release.md) — Separate closing a handle from successfully completing its work.
