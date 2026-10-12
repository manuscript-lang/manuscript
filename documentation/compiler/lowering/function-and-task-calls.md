+++
title = "Function and concurrency API lowering"
weight = 93
+++

# Function and concurrency API lowering

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The compiler turns functions, closures, and contract methods into Go calls. Each generated call carries an internal execution context for cancellation, deadlines, and host service accessors. A closure also keeps its captured snapshots in an environment object. Source code still has one function kind; every function can wait for work.

Explicitly imported TaskGroup, Task, and Scheduler methods lower as typed library calls. Scheduling, cancellation, joining, admission, and shutdown policy live in the standard library/runtime rather than an expanded source intrinsic list. Native runtime primitives start goroutines, signal cancellation, join completion, and synchronize state. The compiler checks the resolved standard API declarations and ordinary callback signatures; a same-spelled application declaration acquires none of that special typing. There is no special background class or task transfer. [Go concurrency specification](https://go.dev/ref/spec#Go_statements)

The hidden context carries the current operation, fixed cancellation parent, effective deadline, cleanup mode, and host roots. TaskGroup operations derive it from the group's construction execution; a scheduler supplies its stored construction-time context. Creating a closure does not capture the caller's execution context as a hidden source dependency; invocation supplies the execution context. Each loop back-edge polls the context's stop signal and unwinds through the iteration's cleanup if it has stopped; cleanup contexts are shielded, so the poll never fires during cleanup.

The frontend checks the source-defined generic signature of TaskGroup.start and the receiver-substituted signature of Task.join. There is no separate callable/result typing rule or runtime pack representation.

Policy can be implemented over native primitives. No goroutine-ID lookup, custom coroutine lowering, stack implementation, or memory collector is required. See [task groups](../../concurrency/task-groups.md) and [background layering](../../standard-library/tasks/scheduler.md).
