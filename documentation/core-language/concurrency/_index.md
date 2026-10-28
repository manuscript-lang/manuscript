+++
title = "Concurrent tasks"
weight = 8
+++

# Concurrent tasks

Run several pieces of work at once with a `TaskGroup`, or spread CPU-bound work over cores with a `WorkerGroup`. Tasks are cooperative and run on one thread, so there is no `async` or `await`: any function can wait, and callers do not change.

1. [Task groups](task-groups.md)
2. [Worker threads](workers.md)
3. [Process groups](process-groups.md): the same shape, in child processes.

| Choose | For | Entry |
| --- | --- | --- |
| `TaskGroup[T, In, Out]` | Cooperative work that waits for I/O or messages | A callable taking `Channel[Out, In]` and returning `T` |
| `WorkerGroup[In, Out]` | CPU work on isolated OS threads | A named zero-argument `def` returning `Unit`; obtains `worker_channel()` |
| `ProcessGroup[T, In, Out]` | Work in child processes, with separate standard streams when needed | A named `def` taking `Channel[Out, In]` and returning `T` |

Each group owns the work it starts until its scope ends. Collect task or process results, or call `worker.wait()`, before leaving the scope to finish the work; leaving early cancels or stops it. Tasks move values through channels; workers and processes serialize messages as JSON. Their cleanup and failure behavior differ: read the relevant guide before choosing a boundary.

`Channel[In, Out]` sends `In` and receives `Out` through typed `send`, `receive` and `close` operations. Its `Transport[In, Out]` supplies the underlying task queue, worker queue or process pipe; see the [channel API](../../standard-library/reference/channels.md).
