+++
title = "Cancellation and budgets"
weight = 62
+++

# Cancellation and budgets

[Guide index](_index.md) · [Design index](../_index.md)

Cancellation asks work to stop. It does not mean the work has already stopped; code must reach a checkpoint, leave its scopes, and finish cleanup. Request work follows the request's execution lifetime. Accepted background work follows its background service's lifetime.

## Requests

Hosts signal requests, joined groups signal their operations, and background services expose cancellation of admitted work:

```text
let id = try background.start(operation: work)
background.cancel(id: id)
```

The submission fragment belongs to a function returning `Result[U, StartError]`; work must have the [standard API contract](../standard-library/types/prelude.md#background-service) callable type. Other application error types need explicit adaptation.

Successful `Background.start` admission yields an `OperationId` through `Result[OperationId, StartError]`. `cancel(id: id)` returns `Unit`, is idempotent for an admitted ID, and requests cancellation without joining. Dropping an ID has no effect. The service retains responsibility for work until it finishes or service shutdown joins it. IDs the service did not admit, including IDs from other services or from joined groups, and IDs whose status has been evicted are harmless no-ops; an ID never identifies unrelated work.

`cancel`, `status`, and `close` are receiver operations of the imported Background service; there are no ambient cancellation or join functions. Using an already-typed service does not require importing its otherwise unused type name. `background.close()` is the waiting boundary: it stops admission and performs the configured drain, cancellation, and joining sequence. A closed service stays closed through all aliases.

Late cancellation cannot overwrite an already committed completion. For background work, the first accepted stop reason determines `WorkStatus`, except that a programming fault during cleanup takes precedence and reports `Crashed`. Joined groups have no per-operation cancellation; their caller-visible outcomes are defined in [joined groups](joining.md#group-lifecycle).

## Propagation and checkpoints

Cancellation is cooperative: stopped work unwinds at its next checkpoint. These are checkpoints:

- runtime operation entry and completion;
- blocking I/O and other adapter calls;
- each loop back-edge, before the next iteration of `for` or `while` starts;
- an explicit `check_cancelled()` call.

Loop checkpoints make CPU-bound loops respond promptly without source changes; they cost one poll of the context's stop signal per iteration. `check_cancelled()` remains available for long straight-line work. It is an imported standard function, not a language intrinsic:

```text
import check_cancelled from "@std/tasks.ms"
```

Importing it supplies the operation declaration; the runtime supplies the current execution context when it is called. Cleanup runs under a shielded context, so checkpoints inside cleanup do not observe the initiating cancellation. No checkpoint occurs between `with` acquisition and cleanup registration; see [completion and acquisition](runtime.md#completion-and-resource-acquisition).

Cancelling a request or current operation cancels its nested groups. Each group joins its operations, each operation runs its registered `with` cleanup, and the caller unwinds.

Background service cancellation reaches the work admitted under that service. Cancellation of a submitting request does not cancel accepted work, because the background lifetime was selected at admission. Cancellation before admission must not start work. Admission and acknowledgement can race with request cancellation; callers must use application idempotency keys if a retried submission must not duplicate work.

Completed external writes remain completed. Cancellation does not provide rollback; a transaction's explicit resource contract does.

Cleanup is shielded from the initiating cancellation and expired work deadline. It may exceed that deadline; it retains capability authority and remains subject to [host escalation](runtime.md#host-escalation). See [foreign cancellation](../modules-and-capabilities/adapters/cancellation.md) and [cleanup faults](../ownership-and-cleanup/cleanup/cleanup-faults.md).

## Timeouts

Timeouts are named library arguments, not syntax annotations. Duration values come from the standard time API; naming `Duration` requires its own import from `@std/time.ms`.

`parallel(tasks: [first, second], timeout: 2.seconds)` sets one budget for the group's execution, starting on API entry after argument preparation. `timeout` is the only budget argument; there is no absolute `deadline` argument.

Argument validation is part of the [standard API contract](../standard-library/types/prelude.md#joined-concurrency); zero-timeout and empty-input behavior is in [joined groups](joining.md#group-lifecycle). On expiry, the group stops, joins, and reports as defined in [joined groups](joining.md#group-lifecycle). Results are never delivered while work remains outstanding.

A timeout bounds ordinary work, not cleanup or joining. Foreign code that does not cooperate can delay joining indefinitely; [host escalation](runtime.md#host-escalation) is the final fallback. An API must not report successful joining merely because its timer expired.

To share one budget across several steps, put the steps in one function and give that function the budget. Nested groups inherit the deadline:

```text
let sync = fn() -> Result[Unit, SyncError]:
    try download_all(sources: sources)
    try upload_all(targets: targets)
    return ok(value: unit)

let [outcome] = try parallel(tasks: [sync], timeout: 2.seconds)
```

This fragment requires an enclosing `Result[U, ExecutionError]` function; `outcome` is the unchanged `Result[Unit, SyncError]`. Any `parallel` inside `download_all` or `upload_all` inherits the same deadline.

## Deadlines

Hosts establish deadlines for application, session, CLI, and request execution contexts. Every operation inherits its fixed parent's deadline. A joined group can only shorten it with `timeout`; nothing in source can extend an inherited deadline. The effective deadline is the earliest of the inherited deadline and any group timeout.

Budgets use the runtime's monotonic timer, not a `Clock` capability or calendar time. A test runner may virtualize that timer; a fake `Clock` value does not affect execution budgets.

When the caller's own deadline expires, the caller unwinds after its groups join; it does not receive `TimedOut`. Only a group's own timeout produces `TimedOut`.

Background work inherits the service's fixed execution context, including that context's deadline. It does not inherit the submitting request's deadline. A service cannot revive cancelled work or extend its host's deadline. Its context is selected at construction, not at each call to `start`.

Deadline configuration is a host operation. There are no source task handles to mutate, deadline annotations on functions, or absolute deadline arguments. See [background services](../standard-library/tasks/background.md) for drain budgets and [adapter contexts](runtime.md#adapter-execution-contexts).
