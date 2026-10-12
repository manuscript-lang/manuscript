+++
title = "Concurrent work"
weight = 4
+++

# Concurrent work

Ordinary calls run sequentially. Use a task group or scheduler when operations should run at the same time. Both accept ordinary functions; there is no separate `async` declaration.

Read these pages in order:

1. [Starting tasks](task-groups.md): run operations together and collect typed results.
2. [Waiting for tasks](joining.md): understand success, failure, and group shutdown.
3. [Cancellation and timeouts](cancellation.md): request a stop and set time budgets.
4. [Scheduling work](scheduling.md): run delayed or repeating work under a service lifetime.
5. [Sharing data](sharing.md): distinguish shared references from safe concurrent access.
6. [Synchronizing updates](synchronization.md): protect a complete read-and-write operation with a lock.
7. [Queues](queues.md): store pending values locally or protect a shared queue.

## Fixed lifetimes

A task group belongs to the execution that constructs it. Its tasks finish and run cleanup before the group closes. A scheduler likewise keeps its construction lifetime; submitting from another request does not change that relationship.

References to a task, scheduler, or resource do not prolong its lifetime. Keep dependencies open until their work finishes, and acquire per-operation resources inside the operation's own `with` block. See [managing resources](../core-language/cleanup/_index.md).

Compiler contributors can read the [runtime contracts](../contributing/concurrent-runtime.md) for transition and acquisition details.
