+++
title = "Scope-exit ordering"
weight = 56
+++

# Scope-exit ordering

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A scope's registered `with` cleanup executes on every exit path. Ordinary aliases and aggregates do not add automatic release actions.

1. Evaluate the pending return value or select the initiating error, fault, or cancellation.
2. Finish any active joined API call: it cancels unfinished operations if needed and joins them before unwinding into the caller's cleanup.
3. Call registered `close()` methods in reverse registration/nesting order. A `Background.close()` performs its own service cancellation and joining here.
4. Deliver the pending return/error, unless cleanup selected a programming fault; otherwise propagate the selected fault or cancellation.

A cleanup fault suppresses a pending normal return or domain error. The unreturned value is released for garbage collection; it is not recursively closed. Resource factories retain explicit responsibility for resources acquired but never delivered.

Returned references do not bypass registered cleanup. A returned file registered in the exiting scope is already closed when the caller receives it. There is no staged ownership transfer or result escrow.

Register dependencies outside the background service's `with` scope so that service shutdown finishes before those dependencies close. See [background services](../../standard-library/tasks/background.md) and [fault selection](cleanup-faults.md).
