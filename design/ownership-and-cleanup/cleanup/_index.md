+++
title = "Scoped cleanup"
weight = 53
+++

# Scoped cleanup

[Guide index](../_index.md) · [Design index](../../_index.md)

Use `with` to register a resource's `close()` operation. Cleanup runs on every exit from that scope and remains separate from successful completion of the resource's work.

- [With scopes](scopes.md)
- [The Closeable contract](closeable.md)
- [Scope-exit ordering](exit-order.md)
- [Shielding and cleanup faults](cleanup-faults.md)
- [External resource release](resource-release.md)
