+++
title = "Cleanup order"
weight = 4
+++

# Cleanup order

When a scope ends, the runtime runs the cleanup registered by `with`. It closes inner resources before outer ones. Another reference to a resource, including one stored in a record, does not register another close action.

1. Evaluate the pending return value or select the initiating error, fault, or cancellation.
2. Finish any active joined API call: it cancels unfinished operations if needed and joins them before unwinding into the caller's cleanup.
3. Call registered `close()` methods in reverse registration/nesting order. A `Scheduler.close()` performs its own service cancellation and joining here.
4. Deliver the pending return/error, unless cleanup selected a programming fault; otherwise propagate the selected fault or cancellation.

A cleanup fault suppresses a pending normal return or domain error. The unreturned value is released for garbage collection; it is not recursively closed. Resource factories retain explicit responsibility for resources acquired but never delivered.

Returned references do not bypass registered cleanup. A returned file registered in the exiting scope is already closed when the caller receives it. There is no staged ownership transfer or result escrow.

Register dependencies outside the scheduler's `with` scope so that service shutdown finishes before those dependencies close. See [scheduling work](../../concurrency/scheduling.md) and [fault selection](cleanup-faults.md).
