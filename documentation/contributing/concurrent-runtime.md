+++
title = "Runtime contracts"
weight = 63
+++

# Runtime concurrency contracts

For runtime implementers. The runtime provides mechanisms to start, stop, join, and synchronize work; library objects decide admission, failure reporting, and shutdown. Source programs use standard concurrency APIs; internal contexts add no source names or compiler bounds.

## Atomic transitions

Each operation has a stable `OperationId`, a fixed execution parent, a stop signal, an effective deadline, and one completion outcome. Cancellation acceptance and completion commitment are atomic; there is no reparenting.

- Admission, closing admission, and capacity reservation are coordinated atomically. If admission wins, the service tracks the operation even if the submitter stops first; if closure or cancellation wins, it never starts.
- A capacity reservation is released exactly once: on rejection or when completion commits. Pending failure reports have their own bound.
- Completion is not published until cleanup and nested joins finish. Cancellation accepted before commitment blocks an ordinary success; committed outcomes are stable.
- Callbacks, failure reporters, cleanup, and joining run outside transition locks. `close()` is idempotent, and concurrent callers wait on one shutdown sequence.
- Synchronized rejects same-operation reentry by work-lifetime identity, including inherited and shielded views. Other operations wait on release or their own cancellation; there is no cross-task wait graph, and cancellation never forcibly releases a holder. Shielded cleanup can block in a lock cycle; deadlines are not a cleanup watchdog.
- An operation must not join itself or an execution ancestor. Closing its own scheduler, even from nested descendants or joined reporters, faults before shutdown starts; check the whole parent chain. Hosts close services from outside their work and order shutdown to avoid cross-service cycles.
- Maps and sets are not synchronized. An access overlapping another task's insert, delete, or clear faults with a message naming `Synchronized` instead of Go's `concurrent map writes` crash. The check is best-effort, and lists get none.

Conformance tests: [semantic tests](compiler/conformance/semantic-tests.md).

## Completion and resource acquisition

Completion records the outcome after the body, nested groups, and cleanup finish. A late stop never overwrites a committed outcome.

- Task results are ordinary values. On group failure, unreturned references are released to the garbage collector; the runtime does not recursively `close()` result fields or captures, which may alias live resources.
- Cleanup responsibility comes from explicit `with` registration or an acquisition API's delivery contract, not result-ownership escrow.
- A native acquisition API must close a resource that cancellation or a fault keeps from delivery.
- Acquisition and `with` registration are one protected sequence: no cancellation checkpoint falls between delivery to the binding and registering `close()`.

| Race outcome | Required handling |
| --- | --- |
| Cancellation wins before delivery | Adapter closes the undelivered resource |
| `with` acquires successfully | Register cleanup before exposing cancellation |
| Cancellation arrives after registration | Unwind the scope and run cleanup |
| Reference retained after scope exit | Memory stays valid; operations report the resource closed |

A source helper returning an open resource must handle resources it acquires but does not return, with an explicit factory or delivery contract. Returning a reference cannot cancel a `with` registration. Scheduler operations deliver no resource values; each manages acquisitions in its own scopes. See [resource release](../core-language/cleanup/resource-release.md).

## Adapter execution contexts

Generated calls carry a hidden execution context exposing the operation's fixed parent, cancellation signal, deadline, and cleanup mode.

- TaskGroup operations derive from the group's construction execution; Scheduler operations from the service's construction-time context, never the submitting request's.
- Cleanup gets a shielded context that ignores the initiating cancellation and expired ordinary deadline. Host escalation policy is separate from the request budget.
- Adapters must close resources safely and not return from a cancelled operation while foreign work is outstanding.

See [runtime/library layering](compiler/lowering/function-and-task-calls.md).

## Host escalation

Joins and cleanup wait for work to end. The runtime cannot terminate a goroutine, so work ignoring cancellation can block a join forever. Escalation is the host's last resort: it ends the process and never reports stuck work as joined.

Each host runs one watchdog, started when the host begins shutdown or gets a stop request (SIGINT, SIGTERM, server shutdown), not by ordinary timeouts. It covers group joins, `Scheduler.close()`, `with` cleanup, and resource close.

| Setting | Default |
| --- | --- |
| Grace period after the stop request | 30 seconds |
| A second stop request during the grace period | Escalates immediately |

On escalation the host:

1. writes one stderr diagnostic per outstanding operation with its `OperationId`, current suspension location, and accepted stop reason;
2. writes retained primary and secondary fault diagnostics;
3. terminates without further cleanup.

The CLI exits 70, labeled incomplete cleanup. Native `RunMain` and the test runner implement the grace period and second-request rule but today write one `incomplete cleanup: <reason>` line, and the grace period is not configurable. Conformance treats an escalated exit as program failure. See [cleanup faults](../core-language/cleanup/cleanup-faults.md).
