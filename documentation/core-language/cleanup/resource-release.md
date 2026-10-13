+++
title = "Closing a resource"
weight = 2
+++

# Closing a resource

Files, sockets, stream bodies, transactions, and owned resources need explicit release. Their object memory is garbage collected, but their external handles or activity are released through `close()` or a `with` block. These resource objects implement `Closeable`.

| Object | Automatic close behavior |
| --- | --- |
| File, socket, stream body | Release the external handle |
| Scheduler service | Stop admission, cancel as configured, and join work |

Cleanup is not successful completion. Explicit commit, finish, or flush operations expose expected errors with `Result`. Unexpected release failures become cleanup faults. A plain `let`, function call, aggregate, or closure does not add implicit close behavior.

Factories close newly acquired native resources when cancellation or an error prevents delivery. A `with` initializer registers successful acquisition before cancellation can unwind it. See [completion and acquisition](../../contributing/concurrent-runtime.md#completion-and-resource-acquisition), [sharing](../../concurrency/sharing.md), and [Closeable](closeable.md).
