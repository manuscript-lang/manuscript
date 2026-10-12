+++
title = "Special call rules"
weight = 3
+++

# Special call rules

The generated reference captures declaration types, bounds, fields, cases, and operations. A few APIs use checker rules beyond an ordinary function signature. These rules are implemented in `checker/calls.go`; this page must be reviewed when those rules change.

Ordinary functions and methods with exactly one declared parameter permit omitting its argument label. Functions with multiple parameters require labels on every supplied argument, including when optional API parameters are omitted. Constructors and contract views retain their labels. Function-type labels remain part of type identity. Source functions with bodies may declare default argument expressions; their evaluation and function-value boundaries are specified in [default arguments](https://manuscript-lang.github.io/manuscript/core-language/functions/declarations-and-calls/#default-arguments).

- `parallel(tasks: [fn() -> T, ...], timeout: Duration)` accepts a literal pack of zero-argument callbacks with possibly different result types. `timeout` is optional. The result is `Result[Pack, ExecutionError]`, where pack positions retain callback result types. Callbacks and results are ordinary values, including functions and contract views. Its result type is computed per call.
- `parallel_map` also accepts optional `timeout: Duration`. Callbacks and results may be any values of the required types. Specialized function values accept the required arguments; optional timeout is available on direct calls.
- `Background(limit: Int, reporter: fn(failure: BackgroundFailure) -> Unit, drain: Duration, history_limit: Int)` requires only `limit`. The other arguments are optional. Reporters and start operations are ordinary callbacks; start may be stored as a bound method.
- `Queue[T]()` creates an unbounded local FIFO. Its optional `capacity: Int` constructor argument sets a fixed positive bound; a nonpositive explicit capacity is a programming fault. Shared access requires `Synchronized[Queue[T]]`.
- `Synchronized[T](value: T)` stores a value behind a mutex. Its `lock()` returns a `SynchronizedGuard[T]` for `with`; guard get/set require an active acquisition, and close releases it.
- `Bytes(values: List[Int])` constructs bytes. The runtime checks the byte range.
- `List`, `Lease`, `SynchronizedGuard`, `Instant`, `Duration`, `Decimal`, and `OperationId` have no source constructor. Lists and durations use literals; other values come from APIs or conversions.
- Records use their listed fields as named constructor arguments. Alternatives construct one listed case. Interfaces describe operations implemented by explicit `impl` declarations; they are capability views rather than concrete resource constructors.
- Native collection methods `map[U]`, `flat_map[U]`, `group_by[K: Hashable]`, `fold[A]`, and `fold_right[A]` infer method type arguments from supplied callbacks/values. Saving a generic method as a value requires explicit specialization, such as `values.map[String]`. Application-defined interface operations remain nongeneric.
- List equality searches require `Equal`; `to_set` requires `Hashable`; `join` is available only on `List[String]`. These receiver requirements are inherited from the shared function declarations.
- Generic bounds constrain type arguments. Pool resources require contract views declaring close. There is no sharing bound or separate callable proof.

For lifetime, cancellation, defaults, and host behavior, read the standard library guides. A type signature alone does not establish these guarantees.
