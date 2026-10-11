+++
title = "Bounded parallel mapping"
weight = 36
+++

# Bounded parallel mapping

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Import `parallel_map` from `@std/tasks.ms`. It runs the same function over a dynamic list, with a bounded number of active invocations. Its result is an ordinary homogeneous list in input order.

```text
let lookup = fn(item: UserId) -> Result[User, UserError]:
    return users.get(id: item)

let outcomes = try parallel_map(
    items: user_ids,
    operation: lookup,
    limit: 8,
)
```

The callable must use the exact parameter label `item`, as declared by the standard binding; each element is supplied as `item: value`. Other labels require an explicit wrapper and are rejected directly. Every invocation's exact result is retained: this example returns `List[Result[User, UserError]]` inside the outer execution `Result`.

Naming Result or ExecutionError in a signature requires their individual imports from `@std/result.ms` and `@std/tasks.ms`. The inferred output list does not require a List import; a source bracket list literal does.

This body fragment requires an enclosing `Result[U, ExecutionError]` function for its outer `try`; translate with `map_error` when using an application error type. Unit tests must match the outer Result instead.

The captured users capability must retain a static shared contract type, such as `Users & Shareable`; a plain Users view cannot supply the callable's sharing proof.

The callable's captured environment, input elements, and output elements must satisfy the concurrent sharing bounds. Returning a resource reference does not register cleanup or keep it open; operations should manage temporary resources within their own `with` scopes.

`limit` must be positive. At most that many operations are active; pending elements remain in the bounded/input storage rather than creating an unbounded set of goroutines. Empty input produces an empty successful list. Domain errors are normal values and do not stop other invocations.

Stopping, joining, timeouts, and outcomes follow the shared [joined-group contract](../../concurrency/joining.md#group-lifecycle); stopping also prevents further items from starting.

This API replaces dynamic source task collections. No application owns, adopts, or retrieves individual task handles. Completion-order streaming is unsupported by this API. Bounded pipelines use the separate queue and background-service contracts.
