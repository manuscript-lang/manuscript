+++
title = "Managing resources"
weight = 7
+++

# Managing resources

Use `with` to close files, sockets, and response bodies at the end of a block, including early returns and errors.

1. [Using `with`](scopes.md)
2. [Closing a resource](resource-release.md)
3. [Implementing `Closeable`](closeable.md)
4. [Cleanup order](exit-order.md)
5. [Cleanup failures](cleanup-faults.md)

A reference keeps an object reachable, not a closed resource open; see [mutation and references](../types/references.md).
