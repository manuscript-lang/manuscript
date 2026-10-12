+++
title = "Waiting for tasks"
weight = 2
+++

# Waiting for tasks

Joining waits for work to finish its body and cleanup. `Task.join()` waits for one successful task; a failed task join waits for its stopped group. `TaskGroup.join()` waits for all submitted work. Closing a group cancels unfinished work and joins it.

## Terms

| Term | Meaning |
| --- | --- |
| Operation | One invocation submitted through `TaskGroup.start` or `Scheduler.start` |
| Group | Operations submitted to one `TaskGroup` |
| Parent | The execution that constructed the group; it fixes cancellation and host roots |
| Joined | Every required operation has finished its body and cleanup |

## Execution errors

`ExecutionError` and its diagnostic `OperationId` are exported by `@std/tasks.ms`:

```manuscript
type ExecutionError:
    case TimedOut
    case Cancelled
    case Crashed(operation: OperationId, message: String)
```

An operation ID identifies work for diagnostics. It does not grant scheduling, cancellation, or joining authority.

## Group lifecycle

1. **Construct.** Store the construction execution as the fixed parent. Register shutdown with that execution's work lifetime; lexical `with` provides an earlier cleanup boundary.
2. **Start.** Each `start` prepares its callback and admits one typed task. A group timeout starts with the first submission. A stopped group returns a stopped handle without invoking further callbacks; a joined or closed group rejects submission with a programming fault.
3. **Stop.** A task fault, timeout, parent cancellation, or explicit close cancels unfinished work. Returning a domain error is ordinary completion. Task outcomes committed before the stop remain available.
4. **Join.** Group joining seals admission and waits for every started operation, including nested service shutdown and cleanup. A successful individual task join leaves admission open. Joining is never bounded by the timeout.
5. **Report.** Group joins and failed task joins use the outcome order below. A successful individual task join returns that task's committed value.

| Condition after joining | Caller observes |
| --- | --- |
| The joining caller's own context was cancelled or reached its inherited deadline | The caller unwinds after cancellation and joining; no Result is delivered |
| A task faulted in its body or cleanup | `error(cause: Crashed(...))` for the first committed fault |
| The group's timeout expired while work was outstanding | `error(cause: TimedOut)` |
| Explicit close cancelled unfinished work, or the fixed parent stopped while another active execution joined | `error(cause: Cancelled)` |
| Otherwise | Group join returns `ok(value: unit)`; task join returns its cached value |

A programming fault takes precedence over a timeout or cancellation outcome. Simultaneous task faults have a scheduling-dependent primary. Outcome commitment and acceptance of a stop share an atomic transition. A completed task is not rerun by joining, and its result is not overwritten by a later stop.

Joining from a cancelled caller cancels and waits for unfinished group work before unwinding. Secondary faults during caller cancellation reach diagnostics. Cleanup remains shielded and may exceed any deadline; uncooperative foreign work falls to [host escalation](../contributing/concurrent-runtime.md#host-escalation).

## Scope cleanup and fault observation

`close()` stops admission, cancels unfinished work, waits for all started operations, and releases the group from its fixed work lifetime. It is safe to close repeatedly or through aliases. Successfully committed task results survive closure; unfinished task handles report cancellation to an active joining execution.

A failed group or task join marks the execution failure observed. Closing a group with an unobserved task programming fault surfaces a cleanup fault, so starting work and dropping its handle cannot silently discard a crash. Returning domain errors does not create a cleanup fault.

Tasks and their descendants cannot join or close their own group or join its task handles. Cross-group cycles are invalid application usage. There is no per-task cancellation; use the group's close boundary or a scheduler's operation-ID cancellation.

See [task groups](task-groups.md), [cancellation](cancellation.md), and [scope cleanup](../core-language/cleanup/exit-order.md).
