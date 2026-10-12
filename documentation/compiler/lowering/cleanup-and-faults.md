+++
title = "Cleanup and fault lowering"
weight = 96
+++

# Cleanup and fault lowering

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The compiler registers `Closeable.close()` after successful `with` initialization and generates cleanup for each block exit. A Go defer that runs only when a function returns is not enough for resources whose lifetime ends at a nested block or loop iteration.

The backend implements [scope-exit order](../../ownership-and-cleanup/cleanup/exit-order.md) and [fault selection](../../ownership-and-cleanup/cleanup/cleanup-faults.md) as follows:

1. Use private tagged Go panics for nonlocal language faults and cancellation.
2. Give each function with active registrations a local scope stack and one deferred unwind handler. Normal block exits drain and pop explicitly; panic paths drain the remaining stack.
3. Pop an action before invoking it, and recover each close separately so a secondary panic cannot skip later cleanup.
4. Give cleanup a context without the initiating cancellation or expired work deadline, retaining authority and cleanup mode.
5. Rethrow the selected fault or cancellation after draining, until its operation or host boundary handles it. Recoverable unexpected adapter panics become programming faults; concurrency boundaries report them as `Crashed`.

A scoped TaskGroup cancels and joins its work at its registered cleanup position, before cleanup of enclosing resources. Ordinary values and captures are never recursively disposed. Process-fatal out-of-memory or stack exhaustion has no cleanup guarantee.

Resources acquired but not delivered require cleanup from the acquisition adapter or factory. Returned references do not suppress an existing with registration. See [exit order](../../ownership-and-cleanup/cleanup/exit-order.md), [fault selection](../../ownership-and-cleanup/cleanup/cleanup-faults.md), and [acquisition races](../../concurrency/runtime.md#completion-and-resource-acquisition).
