+++
title = "External resource release"
weight = 58
+++

# External resource release

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Files, sockets, stream bodies, transactions, and pool leases are ordinary runtime objects implementing `Closeable`. Their memory is garbage collected; release of external handles or activity is explicit or scoped with `with`.

| Object | Automatic close behavior |
| --- | --- |
| File, socket, stream body | Release the external handle |
| Transaction | Roll back if not committed; then release its lease |
| Connection lease | Return the connection only after outstanding access has ended |
| Background service | Stop admission, cancel as configured, and join work |

Closing is shared state: all aliases see the same closed object. Resource methods return resource-specific errors such as `IoError.Closed` after closure. The wrapper must synchronize access and close; checking a flag before accessing a native handle is not sufficient. Old lease references must never access a connection reused for another caller.

Cleanup is not successful completion. Explicit commit, finish, or flush operations expose expected errors with `Result`. Unexpected release failures become cleanup faults. A plain `let`, function call, aggregate, or closure does not add implicit close behavior.

Factories close newly acquired native resources when cancellation or an error prevents delivery. A `with` initializer registers successful acquisition before cancellation can unwind it. See [completion and acquisition](../../concurrency/runtime.md#completion-and-resource-acquisition), [sharing](../values/sharing.md), and [Closeable](closeable.md).
