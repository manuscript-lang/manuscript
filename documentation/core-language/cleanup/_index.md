+++
title = "Managing resources"
weight = 7
+++

# Managing resources

A file, socket, or response body closes when the binding that holds it goes out of scope, including on early returns and errors.

1. [Scope-end cleanup](scopes.md)
2. [Closing a resource](resource-release.md)
3. [Implementing `Closeable`](closeable.md)
4. [Cleanup order](exit-order.md)
5. [Cleanup failures](cleanup-faults.md)

Cleanup answers who releases a resource, and when. It does not by itself prove that a write reached its destination or that a transaction committed. First establish an owner, then handle the operation's Result, and finally release the resource. The chapters below separate those responsibilities.

A borrow does not create another owner or another close action. It must remain within the lifetime of its owner; see [ownership and borrowing](../types/references.md).
