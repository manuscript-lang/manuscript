+++
title = "Cleanup order"
weight = 4
+++

# Cleanup order

On scope exit, cleanup closes inner resources before outer ones, and the bindings of one scope last declared first. Another reference to a resource, including in a record, registers no extra close.

1. Evaluate the pending return value or select the initiating error, fault, or cancellation.
2. Call registered `close()` methods in reverse registration/nesting order.
3. Deliver the pending return/error, unless cleanup selected a programming fault; otherwise propagate the selected fault or cancellation.

A cleanup fault suppresses a pending return or domain error; a value that is not returned gains no implicit `close()` obligation. Ordinary memory drops and resource cleanup are separate. Resource factories remain responsible for resources acquired but never delivered.

Returned references do not bypass cleanup: a file registered in the exiting scope is already closed when the caller receives it. Transferring ownership does not transfer or cancel that registered cleanup.

Declare dependencies in an outer scope, or before the resources that use them, so they close after the resources that use them. See [fault selection](cleanup-faults.md).
