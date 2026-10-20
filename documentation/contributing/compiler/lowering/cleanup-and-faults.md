+++
title = "Cleanup and fault lowering"
weight = 96
+++

# Cleanup and fault lowering

The compiler lowers `with` in `ms-lower`: after successful initialization it registers the binding's `close` and emits the close call on every way out of the block, including nested blocks and loop iterations.

The backend implements [scope-exit order](../../../core-language/cleanup/exit-order.md) and [fault selection](../../../core-language/cleanup/cleanup-faults.md):

1. Normal exits (fall-through, `return`, `break`, `continue`, `try`) call the registered closes in reverse order.
2. Each registration is also an entry on a runtime cleanup stack. A fault aborts the process after the runtime runs the remaining entries in reverse order; generated code does no frame unwinding.
3. Faults call `msrt_fault`, which never returns.

- Values and captures are never recursively disposed by `with`; ordinary values are dropped deterministically at scope end by the ownership rules.
- Out-of-memory and stack exhaustion have no cleanup guarantee.
- Returning a reference does not cancel a `with` registration.
