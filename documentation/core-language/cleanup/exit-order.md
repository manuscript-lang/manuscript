+++
title = "Cleanup order"
weight = 4
+++

# Cleanup order

On scope exit, cleanup closes inner resources before outer ones, and the bindings of one scope last declared first. A borrow registers no extra close. A record or collection that owns resources closes its owned parts; see [holder cleanup](closeable.md#records-and-collections-close-what-they-hold).

1. Evaluate the pending return value or select the initiating error, fault, or cancellation.
2. Call registered `close()` methods in reverse registration/nesting order.
3. Deliver the pending return/error, unless cleanup selected a programming fault; otherwise propagate the selected fault or cancellation.

A cleanup fault can suppress a pending return or domain error; see [cleanup failures](cleanup-faults.md) for fault selection.

Returning an owned resource transfers its cleanup duty to the caller: the exiting scope does not close the moved value. Moving it into a field, collection or escaping closure likewise transfers responsibility to the new owner. A borrowed part cannot escape a local owner that is about to close; returning a borrow of an argument keeps the caller responsible for that owner.

Declare dependencies in an outer scope, or before the resources that use them, so they close after the resources that use them. See [fault selection](cleanup-faults.md).
