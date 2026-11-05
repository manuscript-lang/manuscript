+++
title = "Managing resources"
weight = 7
+++

# Managing resources

A file, socket, or response body closes when the binding that holds it goes out of scope, including on early returns and errors.

1. [Scope-end cleanup](scopes.md): when resources close, how to close early, and in what order
2. [Implementing `Closeable`](closeable.md)
3. [Cleanup failures](cleanup-faults.md)

A reference keeps an object reachable, not a closed resource open; see [mutation and references](../types/references.md).
