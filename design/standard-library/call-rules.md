+++
title = "Special call rules"
weight = 3
+++

# Special call rules

The generated reference captures declaration types, bounds, fields, cases, and operations. A few APIs use checker rules beyond an ordinary function signature. These rules are implemented in `checker/calls.go`; this page must be reviewed when those rules change.

- `parallel(tasks: [fn() -> T, ...], timeout: Duration)` accepts a literal pack of zero-argument callbacks with possibly different result types. `timeout` is optional. The result is `Result[Pack, ExecutionError]`, where pack positions retain callback result types. Callbacks and results must be shareable. Its generated base signature contains `<unknown>` because this result is computed per call.
- `parallel_map` also accepts optional `timeout: Duration`. Its operation and results must be shareable.
- `Background(limit: Int, reporter: fn(failure: BackgroundFailure) -> Unit, drain: Duration, history_limit: Int)` requires only `limit`. The other arguments are optional; `reporter` must be shareable. `Background.start` requires a shareable operation.
- `Bytes(values: List[Int])` constructs bytes. The runtime checks the byte range.
- `List`, `Lease`, `Instant`, `Duration`, `Decimal`, and `OperationId` have no source constructor. Lists and durations use literals; other values come from APIs or conversions.
- Records use their listed fields as named constructor arguments. Alternatives construct one listed case. Contracts describe operations implemented by explicit `impl` declarations; they are capability views rather than concrete resource constructors.
- Generic bounds constrain type arguments. Pool resources require shared contract views. Shared captures and callback restrictions are checked separately from function types.

For lifetime, cancellation, defaults, and host behavior, read the standard library guides. A type signature alone does not establish these guarantees.
