+++
title = "Closing a resource"
weight = 2
+++

# Closing a resource

Files, sockets, stream bodies, and transactions hold external handles released through `close()` or `with`; their memory is garbage collected. They implement `Closeable`.

| Object | Automatic close behavior |
| --- | --- |
| File, socket, stream body | Release the external handle |

Cleanup is not completion. Explicit commit, finish, or flush operations report expected errors with `Result`; unexpected release failures become cleanup faults. A plain `let`, call, aggregate, or closure adds no close behavior.

Factories close newly acquired native resources when cancellation or an error prevents delivery, and a `with` initializer registers acquisition before cancellation can unwind it. See [Closeable](closeable.md).
