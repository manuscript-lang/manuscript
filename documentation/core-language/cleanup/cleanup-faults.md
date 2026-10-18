+++
title = "Cleanup failures"
weight = 5
+++

# Cleanup failures

Cleanup runs when cancellation or a fault ends work, ignoring the cancellation signal and expired deadline that caused the exit (*shielding*). It keeps its access to external services and may wait.

## If close itself faults

Every registered close action is attempted once; a fault in one does not skip the rest.

| Outcome before cleanup | If cleanup faults | If cleanup succeeds |
| --- | --- | --- |
| A programming fault is already pending | Keep the original fault as primary; record cleanup faults as secondary diagnostics. | Keep the original fault. |
| A normal return, expected error, or cancellation is pending | The first cleanup fault becomes primary; record later faults as secondary diagnostics. | Keep the pending outcome. |

A concurrency API reports an operation fault as `ExecutionError.Crashed`; a scheduler uses its failure observer; root hosts isolate and report request failures.

## Cleanup can outlast a timeout

Shielding cannot force uncooperative code to finish. Hosts set cleanup watchdogs separately from request timeouts, and may need [process-level escalation](../../contributing/concurrent-runtime.md#host-escalation) if close or join cannot finish.

Handle expected failures with an explicit fallible method before leaving the scope; for example, commit a transaction rather than relying on close. See [Closeable](closeable.md) and [resource release](resource-release.md).
