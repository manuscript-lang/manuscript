+++
title = "Cleanup and fault lowering"
weight = 96
+++

# Cleanup and fault lowering

The compiler registers `Closeable.close()` after successful `with` initialization and emits cleanup at each block exit. A function-level Go defer is not enough for resources that end at a nested block or loop iteration.

The backend implements [scope-exit order](../../../core-language/cleanup/exit-order.md) and [fault selection](../../../core-language/cleanup/cleanup-faults.md):

1. Nonlocal language faults and cancellation are private tagged Go panics.
2. A function with active registrations gets a local scope stack and one deferred unwind handler. Normal exits drain explicitly; panic paths drain the rest.
3. Pop an action before invoking it, and recover each close separately so a secondary panic cannot skip later cleanup.
4. Cleanup runs in a context without the initiating cancellation or expired deadline, keeping authority and cleanup mode.
5. After draining, rethrow the selected fault or cancellation until its operation or host boundary handles it. Unexpected recoverable adapter panics become programming faults, reported as `Crashed` at concurrency boundaries.

- A scoped TaskGroup cancels and joins at its registered cleanup position, before enclosing resources. Values and captures are never recursively disposed.
- Out-of-memory and stack exhaustion have no cleanup guarantee.
- Undelivered resources are the acquisition adapter's responsibility; returning a reference does not cancel a `with` registration. See [acquisition races](../../concurrent-runtime.md#completion-and-resource-acquisition).
