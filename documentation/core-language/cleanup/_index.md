+++
title = "Managing resources"
weight = 7
+++

# Managing resources

Files, sockets, and response bodies need to close when you finish using them. Use `with` to register that close operation for the end of a block, including early returns and errors.

1. [Using `with`](scopes.md)
2. [Closing a resource](resource-release.md)
3. [Implementing `Closeable`](closeable.md)
4. [Cleanup order](exit-order.md)
5. [Cleanup failures](cleanup-faults.md)

A reference keeps an object accessible; it does not keep a closed resource open. See [mutation and references](../types/references.md). Continue with [files and paths](../../standard-library/filesystem.md) for a concrete library API.
