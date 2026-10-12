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
| Start independent operations and collect typed results | `TaskGroup` | Individual joins retrieve results; group join or scope cleanup waits for all work. |
| Start work under a longer-lived service | `Scheduler` | The service tracks it and waits for unfinished work during shutdown. |

Task groups join submitted work and its cleanup. A group timeout requests a stop; it never waives joining.

Start with [task groups](task-groups.md) for a complete example. Then read [joined groups](joining.md) for error outcomes and [cancellation](cancellation.md) for stopping and time budgets. [Runtime contracts](runtime.md) contains the implementation details.

Concurrency APIs accept ordinary function values, including functions passed through parameters or stored in collections. Closures keep snapshots of the surrounding bindings they use. Keeping a resource reference does not keep the resource open; see [sharing](../ownership-and-cleanup/values/sharing.md).

## Sharing values and updating state

All values may be shared freely, including functions, interface views, collections, and builders. Records and collections are mutable references; local `var` bindings are snapshotted by closures. Services and builders synchronize their internals. Shared records, collections, and local `Queue` instances require an explicit lock around conflicting access. For a complete shared update, import `Synchronized` from `@std/sync.ms`:

```manuscript
import Synchronized from "@std/sync.ms"

let counter = Synchronized(value: 0)
with locked = counter.lock():
    locked.set(value: locked.get() + 1)
```

The guard holds the lock until scope exit. Read the [synchronization contract](../standard-library/data-and-io/synchronized-state.md#synchronized) for cancellation, aliases, and reentry. For a shared FIFO, store a `Queue[T]` inside one `Synchronized` and hold its guard for every access; see [local queues](../standard-library/data-and-io/queues.md#sharing-a-queue). Sharing does not extend a resource's open lifetime.

## Importing concurrency APIs

Concurrency adds no intrinsic names or compiler bounds. Import each API or type that the module names:

```manuscript
import TaskGroup from "@std/tasks.ms"
import Scheduler from "@std/tasks.ms"
import ExecutionError from "@std/tasks.ms"
import OperationId from "@std/tasks.ms"
import StartError from "@std/tasks.ms"
import check_cancelled from "@std/tasks.ms"
import Duration from "@std/time.ms"
```

These are independent imports, not a required bundle. Importing one does not expose the others. Work status and failure reporting are also explicit standard exports; the [standard API contract](../standard-library/types/prelude.md#names-and-identity) lists their paths. Ordinary Result annotations and error-adaptation helpers use their own imports from `@std/result.ms`.

Scheduling, cancellation, joining, time budgets, and service shutdown belong to these library/runtime APIs. The compiler checks ordinary generic callback and Task[T] signatures from the standard source declarations. Its hidden execution context is an internal calling convention and carries host roots used by imported accessors; it is not a source type. Application declarations remain ordinary source declarations.

## Fixed lifetimes

Every operation starts under a fixed execution lifetime. That relationship is chosen before work starts and does not change while it runs.

| API | Execution lifetime |
| --- | --- |
| Ordinary call | Current execution context |
| TaskGroup.start | Group nested under its fixed construction execution |
| `Scheduler.start` | The chosen scheduler's fixed host/component lifetime |

Helpers may pass or return Task[T] handles, but this never changes the group's fixed work lifetime. Closing the group cancels and joins unfinished work regardless of saved handles. Scheduler work is started directly through the chosen service.

Passing a `Scheduler` reference shares access to that service. It does not prolong the service's lifetime, move its existing work, change its cancellation parent, or reset deadlines. The creating scope registers shutdown with `with`; aliases reject admission after closure.

A request can submit work through an application scheduler, but accepted work uses the service's execution context. Request resources captured by that work can still close when the request exits; later use reports the resource's closed-state error. Pass request data and application services, and acquire the operation's resources inside it.

There is no task adoption, task reparenting, source-level detached work, or dynamic ownership graph. Scoped resources and ordinary references follow [resource lifetimes](../ownership-and-cleanup/_index.md).

## Reading order

1. [Task groups](task-groups.md): starting tasks, argument preparation, and typed results
2. [Joined groups](joining.md): the normative stop, join, and outcome contract for task groups
3. [Cancellation and budgets](cancellation.md): cancellation requests, checkpoints, timeouts, and deadlines
4. [Synchronized values](../standard-library/data-and-io/synchronized-state.md): lock scopes, complete updates, aliases, and reentry
5. [Runtime contracts](runtime.md): atomic transitions, resource acquisition, adapter contexts, and host escalation

The standard library describes [schedulers](../standard-library/tasks/scheduler.md).
