+++
title = "Joined groups"
weight = 61
+++

# Joined groups and execution outcomes

[Guide index](_index.md) · [Design index](../_index.md)

A parallel call waits for all the operations it started, including their cleanup. This waiting is called joining. A failure or timeout first asks unfinished work to stop, then waits for it. This page defines the exact lifecycle and which outcome the caller receives.

## Terms

| Term | Meaning |
| --- | --- |
| Operation | One invocation of a function passed to a concurrency API: a `tasks` position, one `parallel_map` item, or one `Background.start` submission |
| Group | The operations started by one `parallel` or `parallel_map` call |
| Caller | The execution that called the API; its context is the group's fixed parent |
| Joined | Every started operation has finished its body and scope cleanup |

## Execution errors

`ExecutionError` is exported by `@std/tasks.ms`; import it when naming the result type. Its Crashed payload uses `OperationId`, also exported by `@std/tasks.ms`. The standard declaration is:

```text
type ExecutionError:
    case TimedOut
    case Crashed(operation: OperationId, message: String)
```

`OperationId` identifies runtime work for diagnostics; it does not grant scheduling, joining, or transfer authority. Secondary faults are retained in runtime diagnostics associated with the primary outcome.

## Group lifecycle

1. **Prepare.** The caller evaluates arguments in written order. If preparation fails, no operation starts. See [preparation](parallel.md#preparation).
2. **Start.** An empty pack or list returns `ok` immediately and starts no work, whatever the timeout. A zero timeout on nonempty input stops the group before any operation starts. Otherwise `parallel` starts every position and `parallel_map` keeps at most `limit` operations active.
3. **Stop.** The first of these triggers stops the group: an operation faults, the group's `timeout` expires, or the caller's context is cancelled or reaches its inherited deadline. Stopping prevents further starts and requests cancellation of unfinished operations. Returning a domain `error(cause: ...)` is ordinary completion and never stops the group.
4. **Join.** The API waits for every started operation, including its cleanup. Joining is not bounded by the timeout; uncooperative work falls to [host escalation](runtime.md#host-escalation).
5. **Report.** After joining, the caller observes the first matching row:

| Condition after joining | Caller observes |
| --- | --- |
| The caller's own context was cancelled or reached its inherited deadline | The caller unwinds; no Result is delivered. Operation faults become secondary diagnostics |
| An operation faulted, in its body or cleanup | `error(cause: Crashed(...))` for the primary fault |
| The group's `timeout` expired before every operation committed | `error(cause: TimedOut)` |
| Otherwise | `ok(value: ...)` with each operation's exact return value in input order |

The first row is checked against the caller's context, not the group's derived context. Both can report an expired deadline; only the group's own timer yields `TimedOut`, and only to a caller that is still active.

The primary fault is the first fault committed to the group's outcome. When operations fault concurrently, which one is primary depends on scheduling. Successful value order never does. Commitment of an operation's outcome and acceptance of a stop are atomic; an operation that committed before the stop keeps its outcome. See [atomic transitions](runtime.md#atomic-transitions).

## Faults are isolated at the group boundary

An operation fault becomes `Crashed` rather than unwinding the caller. This is intentional and matches how hosts isolate a failed request: the faulted operation has already unwound through its own cleanup, its siblings have been cancelled and joined, and the caller is the only remaining place that can respond. No faulted state is resumed. The caller's own faults still unwind it; [try](../core-language/errors/propagation.md) propagates only `Result` errors.

## No per-operation cancellation

No source or adapter API cancels a single operation of a joined group. An adapter that ends a foreign call early reports that through the operation's declared return value, such as an `IoError`; it is not a fault. Joined APIs therefore have no separate cancelled outcome. Background work, which can be cancelled individually, reports cancellation through `WorkStatus.Cancelled`.

See [parallel operations](parallel.md), [cancellation](cancellation.md), and [scope cleanup](../ownership-and-cleanup/cleanup/exit-order.md).
