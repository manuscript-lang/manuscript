+++
title = "Cleanup failures"
weight = 5
+++

# Cleanup failures

Cleanup also runs when cancellation or a fault ends work. It is *shielded*: the cancellation signal and expired deadline that caused the exit do not apply to it, so it keeps its access to external services and may wait.

## If close itself faults

Every registered close action is attempted once; a fault in one does not skip the rest.

| Outcome before cleanup | If cleanup faults | If cleanup succeeds |
| --- | --- | --- |
| A programming fault is already pending | Keep the original fault as primary; record cleanup faults as secondary diagnostics. | Keep the original fault. |
| A normal return, expected error, or cancellation is pending | The first cleanup fault becomes primary; record later faults as secondary diagnostics. | Keep the pending outcome. |

For a request handler, return an expected error response before leaving the handler when recovery is possible; a fault is reported by the host running it.

## Cleanup can outlast a timeout

A request timeout does not put a time limit on its cleanup, and shielding cannot force an operation that never finishes to return. Keep cleanup bounded. After a process stop signal, the runtime applies a separate shutdown grace period and may use [process-level escalation](https://github.com/manuscript-lang/manuscript/blob/main/documentation/contributing/runtime-conventions.md#host-escalation) if work cannot finish.

## Close errors are not faults

A close that returns an error is not a fault when the function can return it: the error becomes the function's result (see [Closeable](closeable.md#a-close-returns-a-result)). When you need to react to a failure, such as a failed transaction, commit or close explicitly instead of relying on scope-end close. See [Closeable](closeable.md) and [closing a resource explicitly](scopes.md#close-a-resource-explicitly).
