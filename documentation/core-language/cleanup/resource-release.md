+++
title = "Closing a resource"
weight = 2
+++

# Closing a resource

Files, sockets, stream bodies, and transactions hold external handles released through `close()` or by the scope that owns them; their memory is dropped according to ownership rules, separately from releasing the external handle. They implement `Closeable`.

| Object | Automatic close behavior |
| --- | --- |
| File, socket, stream body | Release the external handle |

Cleanup is not completion. `close()` returns a `Result` and a failed scope-end close is returned or faults; explicit commit, finish, or flush operations report expected errors with `Result`. A value that is not a resource, such as a `List[Int]` or a closure that captures none, adds no close behavior.

Factories close newly acquired native resources when cancellation or an error prevents delivery, and a binding registers its close right after the initializer succeeds, before cancellation can unwind it. See [Closeable](closeable.md).
