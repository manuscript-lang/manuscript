+++
title = "Concurrency"
weight = 59
+++

# Concurrency guide

[Design index](../_index.md)

An ordinary function call finishes before the caller moves on. Use a concurrency API when operations should run at the same time. Every function can wait for work; there is no separate `async` declaration.

## Choose how the work ends

| Need | Use | When it finishes |
| --- | --- | --- |
| Run a fixed set of functions together | `parallel` | Before the call returns, including on failure. |
| Run one function over a list, with limited concurrency | `parallel_map` | Before the call returns, including on failure. |
| Start work under a longer-lived service | `Background` | The service tracks it and waits for unfinished work during shutdown. |

Parallel APIs *join*: they wait for every started operation to finish its body and cleanup. A timeout requests a stop; it does not let the call return with work still running.

Start with [parallel operations](parallel.md) for a complete example. Then read [joined groups](joining.md) for error outcomes and [cancellation](cancellation.md) for stopping and time budgets. [Runtime contracts](runtime.md) contains the implementation details.

Functions passed to a concurrency API must be safe to call concurrently. Closures keep snapshots of the surrounding bindings they use. Keeping a resource reference does not keep the resource open; see [sharing](../ownership-and-cleanup/values/sharing.md).

## Importing concurrency APIs

Concurrency adds no intrinsic names or compiler bounds. Import each API or type that the module names:

```text
import parallel from "@std/tasks.ms"
import parallel_map from "@std/tasks.ms"
import Background from "@std/tasks.ms"
import ExecutionError from "@std/tasks.ms"
import OperationId from "@std/tasks.ms"
import StartError from "@std/tasks.ms"
import check_cancelled from "@std/tasks.ms"
import Duration from "@std/time.ms"
```

These are independent imports, not a required bundle. Importing one does not expose the others. Work status and failure reporting are also explicit standard exports; the [standard API contract](../standard-library/types/prelude.md#names-and-identity) lists their paths. Ordinary Result annotations and error-adaptation helpers use their own imports from `@std/result.ms`.

Scheduling, cancellation, joining, time budgets, and service shutdown belong to these library/runtime APIs. The compiler checks callable sharing and the fixed parallel pack shape by the resolved standard binding identity. Its hidden execution context is an internal calling convention, not an ambient source capability or a new intrinsic type. A user function named parallel remains an ordinary function.

## Fixed lifetimes

Every operation starts under a fixed execution lifetime. That relationship is chosen before work starts and does not change while it runs.

| API | Execution lifetime |
| --- | --- |
| Ordinary call | Current execution context |
| `parallel` or `parallel_map` | Joined group nested under the caller |
| `Background.start` | The chosen background service's fixed host/component lifetime |

A helper may call `parallel` and return its completed result. It cannot return running work for another scope to adopt. Background work is started directly through the chosen service.

Passing a `Background` reference shares access to that service. It does not prolong the service's lifetime, move its existing work, change its cancellation parent, or reset deadlines. The creating scope registers shutdown with `with`; aliases reject admission after closure.

A request can submit work through an application background service, but accepted work uses the service's execution context. Request resources captured by that work can still close when the request exits; later use reports the resource's closed-state error. Pass request data and application services, and acquire the operation's resources inside it.

There is no task adoption, task reparenting, source-level detached work, or dynamic ownership graph. Scoped resources and ordinary references follow [resource lifetimes](../ownership-and-cleanup/_index.md).

## Reading order

1. [Parallel operations](parallel.md): calling `parallel`, argument preparation, and typed results
2. [Joined groups](joining.md): the normative stop, join, and outcome contract for `parallel` and `parallel_map`
3. [Cancellation and budgets](cancellation.md): cancellation requests, checkpoints, timeouts, and deadlines
4. [Runtime contracts](runtime.md): atomic transitions, resource acquisition, adapter contexts, and host escalation

The standard library pages cover [bounded parallel mapping](../standard-library/tasks/parallel-map.md) and [background services](../standard-library/tasks/background.md).
