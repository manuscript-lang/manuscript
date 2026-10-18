+++
title = "Function and concurrency API lowering"
weight = 93
+++

# Function and concurrency API lowering

Functions, closures, and contract methods lower to Go calls that carry a hidden execution context (cancellation, deadlines, host service accessors). A closure also keeps its captured snapshots in an environment object. Source has one function kind, and every function can wait.

- TaskGroup, Task, and Scheduler methods lower as typed library calls. Scheduling, cancellation, joining, admission, and shutdown policy live in the standard library and runtime; native primitives start goroutines, signal cancellation, join, and synchronize. A same-spelled application declaration gets none of the special typing. There is no background class or task transfer. [Go concurrency specification](https://go.dev/ref/spec#Go_statements)
- The context carries the current operation, fixed cancellation parent, deadline, cleanup mode, and host roots. TaskGroup operations derive it from the group's construction execution, and a scheduler supplies its construction-time context. Closure creation does not capture the caller's context; invocation supplies it.
- Each loop back-edge polls the stop signal and unwinds through the iteration's cleanup. Cleanup contexts are shielded, so the poll never fires during cleanup.
- The frontend checks the generic signature of `TaskGroup.start` and the receiver-substituted `Task.join`; there is no separate callable typing rule or pack representation.

No goroutine-ID lookup, custom coroutine lowering, stack implementation, or collector is required.
