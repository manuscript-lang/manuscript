+++
title = "Shielding and cleanup faults"
weight = 57
+++

# Shielding and cleanup faults

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Cleanup still runs when cancellation or a fault ends ordinary work. It ignores the cancellation signal and expired work deadline that caused the exit. This is called *shielding*. Cleanup keeps the original access to external services and may wait for operations to finish.

## If close itself faults

Every registered close action is attempted once during scope exit. A fault in one action does not skip the rest.

| Outcome before cleanup | If cleanup faults | If cleanup succeeds |
| --- | --- | --- |
| A programming fault is already pending | Keep the original fault as primary; record cleanup faults as secondary diagnostics. | Keep the original fault. |
| A normal return, expected error, or cancellation is pending | The first cleanup fault becomes primary; record later faults as secondary diagnostics. | Keep the pending outcome. |

A concurrency API reports an operation fault as `ExecutionError.Crashed`. A background service reports it through its failure observer. Root hosts isolate and report request failures.

## Cleanup can outlast a timeout

Shielding gives cleanup a chance to release resources; it cannot force uncooperative code to finish. Hosts set cleanup watchdogs separately from request timeouts. If close or join cannot finish, the host may need [process-level escalation](../../concurrency/runtime.md#host-escalation). A timer expiring does not mean cleanup completed.

If an operation can fail in an expected way, handle that through an explicit fallible completion method before leaving the scope. For example, commit a transaction before relying on close to release it. See [Closeable](closeable.md), [timeouts](../../concurrency/cancellation.md#timeouts), and [resource release](resource-release.md).
