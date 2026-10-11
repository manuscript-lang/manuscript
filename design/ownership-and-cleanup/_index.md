+++
title = "Resource lifetimes and cleanup"
weight = 47
+++

# Resource lifetimes and cleanup

[Design index](../_index.md)

Ordinary values and object references use Go garbage collection. Explicit `with` scopes release external resources through the `Closeable` contract. Capturing, returning, storing, or passing a reference does not transfer cleanup or keep a resource open.

There is no move operation, borrowed parameter kind, or consuming closure type.

## Reading order

### 1. References and sharing

- [Ordinary references](values/references.md)
- [Concurrent access and resource lifetime](values/sharing.md)
- [Aggregates and local construction](values/aggregates.md)
- [Assignment and branches](values/control-flow.md)

### 2. Scoped cleanup

- [With scopes](cleanup/scopes.md)
- [The Closeable contract](cleanup/closeable.md)
- [Scope-exit ordering](cleanup/exit-order.md)
- [Shielding and cleanup faults](cleanup/cleanup-faults.md)
- [External resource release](cleanup/resource-release.md)
