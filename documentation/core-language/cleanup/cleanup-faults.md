+++
title = "Cleanup failures"
weight = 5
+++

# Cleanup failures

Cleanup runs when cancellation or a fault ends work, ignoring the cancellation signal and expired deadline that caused the exit (*shielding*). It keeps its access to external services and may wait.

This matters when an operation times out while holding a resource. The original work must stop, but releasing the resource may itself need to wait. Reusing the expired deadline for the release would interrupt cleanup at exactly the moment it is needed. Shielding lets that release finish; it does not turn the interrupted operation into a success.

## If close itself faults

Every registered close action is attempted once; a fault in one does not skip the rest.

| Outcome before cleanup | If cleanup faults | If cleanup succeeds |
| --- | --- | --- |
| A programming fault is already pending | Keep the original fault as primary; record cleanup faults as secondary diagnostics. | Keep the original fault. |
| A normal return, expected error, or cancellation is pending | The first cleanup fault becomes primary; record later faults as secondary diagnostics. | Keep the pending outcome. |

For a request handler, return an expected error response before leaving the handler when recovery is possible; a fault is reported by the host running it.

## Cleanup can outlast a timeout

A request timeout does not put a time limit on its cleanup. Keep cleanup bounded: shielding cannot force an operation that never finishes to return. After a process stop signal, the runtime applies a separate shutdown grace period and may use [process-level escalation](../../contributing/runtime-conventions.md#host-escalation) if work cannot finish.

A close that returns an error is not a fault where the function can return it: the error becomes the function's result (see [Closeable](closeable.md#a-close-returns-a-result)). Commit a transaction explicitly rather than relying on close when you need to react to its failure. See [Closeable](closeable.md) and [resource release](resource-release.md).
