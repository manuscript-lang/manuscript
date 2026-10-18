+++
title = "Cleanup order"
weight = 4
+++

# Cleanup order

On scope exit, `with` cleanup closes inner resources before outer ones. Another reference to a resource, including in a record, registers no extra close.

1. Evaluate the pending return value or select the initiating error, fault, or cancellation.
2. Finish any active joined API call: it cancels unfinished operations if needed and joins them before unwinding into the caller's cleanup.
3. Call registered `close()` methods in reverse registration/nesting order. A `Scheduler.close()` performs its own service cancellation and joining here.
4. Deliver the pending return/error, unless cleanup selected a programming fault; otherwise propagate the selected fault or cancellation.

A cleanup fault suppresses a pending return or domain error; the unreturned value is garbage collected, not closed. Resource factories remain responsible for resources acquired but never delivered.

Returned references do not bypass cleanup: a file registered in the exiting scope is already closed when the caller receives it. There is no ownership transfer.

Register dependencies outside the scheduler's `with` so service shutdown finishes first. See [fault selection](cleanup-faults.md).
