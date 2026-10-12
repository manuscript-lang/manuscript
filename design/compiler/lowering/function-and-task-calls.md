+++
title = "Function and concurrency API lowering"
weight = 93
+++

# Function and concurrency API lowering

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

The compiler turns functions, closures, and contract methods into Go calls. Each generated call carries an internal execution context for cancellation, deadlines, and host service accessors. A closure also keeps its captured snapshots in an environment object. Source code still has one function kind; every function can wait for work.

Explicitly imported `parallel`, and `Background` methods lower as typed library calls. Scheduling, cancellation, joining, admission, and shutdown policy live in the standard library/runtime rather than an expanded source intrinsic list. Native runtime primitives start goroutines, signal cancellation, join completion, and synchronize state. The compiler checks the resolved standard API declarations and ordinary callback signatures; a same-spelled application declaration acquires none of that special typing. There is no special background class or task transfer. [Go concurrency specification](https://go.dev/ref/spec#Go_statements)

The hidden context carries the current operation, fixed cancellation parent, effective deadline, cleanup mode, and host roots. Parallel operations derive it from the caller; a background service supplies its stored construction-time context. Creating a closure does not capture the caller's execution context as a hidden source dependency; invocation supplies the execution context. Each loop back-edge polls the context's stop signal and unwinds through the iteration's cleanup if it has stopped; cleanup contexts are shielded, so the poll never fires during cleanup.

The frontend implements the [standard library's fixed heterogeneous callable/result mapping](../../standard-library/types/prelude.md#joined-concurrency), preserving inferred packs through locals, generic helpers, and Result matches. This is type-system/interop support for the API. General source pack syntax is unsupported; the standard mapping is normative and cannot be altered by an adapter manifest.

Policy can be implemented over native primitives. No goroutine-ID lookup, custom coroutine lowering, stack implementation, or memory collector is required. See [parallel](../../concurrency/parallel.md) and [background layering](../../standard-library/tasks/background.md).
