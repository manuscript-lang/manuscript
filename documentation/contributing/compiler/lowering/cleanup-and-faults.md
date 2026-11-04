+++
title = "Cleanup and fault lowering"
weight = 96
+++

# Cleanup and fault lowering

The compiler lowers scope-end cleanup in `ms-lower` (`close.rs`): after a resource binding's initializer succeeds it registers the binding's `close` and emits the close call on every way out of the scope, including nested blocks and loop iterations.

The backend implements [scope-exit order](../../../core-language/cleanup/exit-order.md) and [fault selection](../../../core-language/cleanup/cleanup-faults.md):

1. Normal exits (fall-through, `return`, `break`, `continue`, `try`) call the registered closes in reverse order.
2. Runtime cleanup entries cover faults and cancellation. Guards let a promise or `expect_fault` contain a fault after cleanup; an unhandled root fault ends the program.
3. Faulting operations report through the runtime's nonreturning fault path. Generated drop and close entries release values when guarded work unwinds.

- Records, alternatives and collections close the resource parts they own. Escaping closures own their captures; borrowed captures add no cleanup duty.
- Moving a resource out transfers its cleanup duty. A partial move leaves cleanup for the resource parts still owned by the original binding.
- Reassignment closes the replaced resource before the new owned value takes its place.
- Checked stack exhaustion reports a fault and runs cleanup; out-of-memory termination has no cleanup guarantee. See [programming faults](../../../core-language/errors/faults.md#runaway-recursion).

The close helpers in `ms-lower/src/close.rs` and guarded unwind entries in `ms-mir` implement these paths; validate them with the resource and ownership tests, not just successful compilation.
