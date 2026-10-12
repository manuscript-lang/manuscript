+++
title = "Scoped cleanup"
weight = 53
+++

# Scoped cleanup

[Guide index](../_index.md) · [Design index](../../_index.md)

A `with` block registers a resource to close when the block ends. Cleanup also runs after early returns, errors, faults, and cancellation. Start with with scopes, then read the exact rules for close and exit order.

- [With scopes](scopes.md) — Acquire a resource and close it at the end of a block with `with`.
- [The Closeable contract](closeable.md) — Implement the cleanup operation required by `with`.
- [Scope-exit ordering](exit-order.md) — Follow cleanup order after a return, error, fault, or cancellation.
- [Shielding and cleanup faults](cleanup-faults.md) — Understand cleanup after cancellation and what happens if close itself faults.
- [External resource release](resource-release.md) — Separate closing a handle from successfully completing its work.
