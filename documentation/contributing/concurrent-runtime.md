+++
title = "Runtime contracts"
weight = 63
+++

# Runtime concurrency contracts

This page is for runtime implementers. The runtime provides the mechanisms to start, stop, join, and synchronize work. Library objects decide whether to accept work, how to report failures, and how shutdown proceeds.

Source programs use standard concurrency APIs. The compiler checks their types, callback signatures, and cleanup contracts. Internal contexts and scheduler mechanisms add no source names or compiler bounds.

## Atomic transitions

Each runtime operation has a stable `OperationId`, a fixed execution parent, a stop signal, an effective deadline, and one completion outcome. Cancellation acceptance and completion commitment have atomic linearization points. There is no reparenting or task-transfer transaction.

Scheduler admission, closing admission, and reserving capacity must be coordinated atomically. If admission wins, the service tracks the accepted operation even if the submitting request stops before receiving its ID. If closure or cancellation wins before admission, the operation never starts. Capacity reservations are released exactly once: on rejection, or when the operation's completion commits. Pending failure reports have their own bound and do not hold admission capacity.

Completion is not published until registered cleanup and nested joins have finished. A pending cancellation accepted before commitment prevents an ordinary successful outcome from being delivered. Already committed outcomes are stable.

User callbacks, failure reporters, resource cleanup, and joining run outside transition locks. Shutdown is idempotent; concurrent calls to `close()` observe one shutdown sequence and all wait for it to finish.

Synchronized rejects same-operation reentry using execution/work-lifetime identity, including inherited and shielded views. Different operations wait on release or their current context's cancellation signal; the runtime maintains no cross-task wait graph. Cancellation does not forcibly release an executing holder or abandon joined cleanup. Shielded cleanup can remain blocked in a cross-task lock cycle; ordinary deadlines are not a cleanup watchdog. See synchronization and native shutdown limits.

An operation must not join itself or an execution ancestor. Closing its own scheduler, including from nested task-group descendants or reporter callbacks joined by that service, faults before initiating shutdown. Check the fixed execution-parent chain, not just the current operation ID. Hosts close services from outside their admitted work. Cross-service cyclic shutdown is invalid library usage and must be avoided by host shutdown ordering.

The conformance suite uses controlled barriers and race stress for admission versus closure, cancellation versus completion, and concurrent shutdown. See [semantic tests](compiler/conformance/semantic-tests.md).

## Completion and resource acquisition

Completion records an operation's outcome after its body, nested concurrency groups, and registered cleanup finish. Cancellation and completion commitment race atomically; a late stop does not overwrite a committed outcome.

Task results are ordinary values, with references to existing objects where appropriate. If the group fails, unreturned references are released for garbage collection. The runtime does not recursively call `close()` on arbitrary result fields or closure captures: those references may alias resources still used elsewhere. Cleanup responsibility comes from explicit `with` registration or an acquisition API's delivery contract, not a result-ownership escrow.

A native acquisition API must close a newly acquired resource if cancellation or a fault prevents it from being delivered. Successful acquisition and registration by `with` form one protected sequence: no cancellation checkpoint may occur between delivery to the binding and registration of its `close()` action.

| Race outcome | Required handling |
| --- | --- |
| Cancellation wins before delivery | Acquisition adapter closes the undelivered resource |
| `with` acquires successfully | Register cleanup before exposing cancellation |
| Cancellation arrives after registration | Unwind the scope and run registered cleanup |
| Closure/result retains a resource reference after scope exit | The reference remains valid memory; operations report that the resource is closed |

A source helper returning an open resource must handle resources it acquires but fails to return. Its resource factory/delivery contract is explicit. Merely returning a resource reference cannot cancel a `with` registration or keep the resource open.

Scheduler operations have no resource-valued result delivery; each operation manages acquisitions through its own scopes. See [resource release](../core-language/cleanup/resource-release.md).

## Adapter execution contexts

Generated calls carry a hidden execution context. An adapter observes the current operation's fixed parent context, cancellation signal, deadline, and cleanup mode.

TaskGroup operations derive contexts from the group's fixed construction execution. Scheduler operations derive contexts from their service's construction-time context. The runtime does not substitute the submitting request's context merely because `start` was invoked from that request.

Operation IDs support diagnostics and traces.

Cleanup receives a shielded context that ignores the initiating cancellation and expired ordinary-work deadline. It preserves authority; a host cleanup/escalation policy is separate from the request budget. Adapters must support safe resource closure and must not return from a cancelled operation while its foreign work is still outstanding.

See deadlines, and [runtime/library layering](compiler/lowering/function-and-task-calls.md).

## Host escalation

Joining and cleanup wait for work to actually end. The runtime cannot safely terminate an arbitrary goroutine, so work that ignores cancellation can delay a join forever. Escalation is the host's last resort for that case. It ends the process; it never reports the stuck work as joined.

Each host runs one watchdog. It starts when the host begins shutdown or receives a stop request, such as SIGINT, SIGTERM, or server shutdown. Ordinary timeouts and request deadlines do not start it. Once started, it covers every waiting boundary: group joins, `Scheduler.close()`, `with` cleanup, and resource close.

| Setting | Default |
| --- | --- |
| Grace period after the stop request | 30 seconds |
| A second stop request during the grace period | Escalates immediately |

Hosts may configure a different grace period. A zero grace period escalates on the first stop request whenever work is still outstanding.

On escalation the host:

1. writes one diagnostic per outstanding operation to host stderr, containing its `OperationId`, the source location of its current suspension, and its accepted stop reason;
2. writes any retained primary and secondary fault diagnostics;
3. terminates the process without running further cleanup.

The CLI host exits 70 and labels the exit as incomplete cleanup. Conformance treats an escalated exit as a failure of the program, not as successful shutdown. See CLI exit and shutdown, HTTP shutdown, and [cleanup faults](../core-language/cleanup/cleanup-faults.md).
