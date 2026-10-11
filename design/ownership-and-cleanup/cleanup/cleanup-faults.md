+++
title = "Shielding and cleanup faults"
weight = 57
+++

# Shielding and cleanup faults

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Cleanup runs even when the initiating execution was cancelled or faulted. It ignores the initiating cancellation and expired work deadline while retaining the original capability authority. It may suspend.

Each registered action is attempted once by its scope exit. A fault in one action does not skip remaining actions. The first programming fault is primary; later cleanup faults are attached as secondary diagnostics. If no programming fault was already pending, a cleanup fault replaces a normal return, domain error, or cancellation. Without a cleanup fault, the initiating outcome is preserved.

At a concurrency API boundary a programming fault produces `Crashed` in the outer `ExecutionError`. At a background boundary it is reported by the service. Root hosts isolate and report request failures.

Hosts configure cleanup watchdogs and [escalation](../../concurrency/runtime.md#host-escalation) independently of request timeouts. Shielding does not guarantee that uncooperative code terminates, and a timer cannot make a still-running close/join count as completed. The runtime may require process-level escalation.

Expected failures are handled through explicit fallible completion methods before scope exit. See [Closeable](closeable.md), [timeouts](../../concurrency/cancellation.md#timeouts), and [resource release](resource-release.md).
