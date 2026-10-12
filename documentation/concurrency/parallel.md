+++
title = "Parallel operations"
weight = 60
+++

# Parallel operations

[Guide index](_index.md) · [Design index](../_index.md)

Use `parallel` to run a fixed set of operations at the same time. Pass functions in the named `tasks` argument. The API starts them and waits for every started operation, including cleanup, before returning. Passing a function call would execute it before parallel starts.

## Calling parallel

```manuscript
import Result from "@std/result.ms"
import { ExecutionError, parallel } from "@std/tasks.ms"

fn combine() -> Result[String, ExecutionError]:
    let first = fn() -> String: return "hello"
    let second = fn() -> Int: return 42

    let [text, number] = try parallel(tasks: [first, second])
    return ok(value: "{text} {number}")
```

`try` propagates an execution error. On success, `text` is a `String` and `number` is an `Int`.

## Preparation

Before parallel starts anything, the caller evaluates arguments, task-pack entries, receivers, and captured values in written order. In this example, creating `first` and `second` creates function values. Their bodies run later, after preparation succeeds and parallel starts the operations under its group execution context.

If preparation fails, no operation has started. Preparation may have external effects; the runtime does not undo them. Resources acquired during preparation require their own `with` scopes or acquisition API contracts.

Passing `first()` instead of `first` executes that call during preparation; it is not a way to schedule the call concurrently, and it is a type error when the result is not callable. Ordinary calls inside a function remain sequential unless another concurrency API is invoked.

Concurrent scheduling and external effect order are nondeterministic. Sharing a resource does not imply that simultaneous operations on it are semantically valid; its API must serialize access or report unsupported concurrent use. See [closures](../core-language/functions/function-values-and-closures.md) and [resource sharing](../ownership-and-cleanup/values/sharing.md).

## Ordered, typed results

A literal task pack is a fixed set of positions, each holding a zero-argument function. Positions may have different return types. The result preserves both their types and their input order. Here, `text` is a `String` and `number` is an `Int`, whichever operation finishes first.

The brackets do not force these different types into a homogeneous `List[T]`. Fixed positional packs require type-system support for heterogeneous inputs and outputs; `parallel` itself remains an API call, with no special concurrency keyword. Ordinary list literals outside a positional-pack contract keep their homogeneous list rules.

Pack arity is preserved: `parallel(tasks: [first])` returns a one-position successful result, destructured with `let [resA] = ...`; an empty pack returns an empty successful result and starts no work. Destructuring a fixed positional result with the wrong number of positions is a compile error. Parenthesized binding patterns such as `let (resA, resB) = ...` are not supported. See [destructuring bindings](../core-language/basics/destructuring.md).

## Return values and errors

`parallel` returns an outer `Result[Pack, ExecutionError]`. The outer Result describes execution of the whole group. Each operation's return value is preserved unchanged at its position:

| Function returns | Result position contains |
| --- | --- |
| `String` | `String` |
| `Result[T, E]` | `Result[T, E]` |
| `Optional[String]` | `Optional[String]` |

A returned domain `error(cause: ...)` is ordinary completion. It does not stop sibling operations and is not flattened into the outer Result. Use `match` when choosing a response for different outcomes and `try` when forwarding a compatible error; see [error compatibility](../core-language/errors/propagation.md#error-compatibility). There is no source task-result wrapper beyond the outer Result.

No operation remains running after `parallel` exits, on any path. An operation fault or an expired `timeout` stops and joins the group; caller cancellation joins the group and then unwinds the caller. The complete rules are in [joined groups](joining.md#group-lifecycle).

Results follow the [ordinary reference rules](../ownership-and-cleanup/values/references.md); returning a resource does not keep it open. Unreturned references become eligible for garbage collection; the runtime does not recursively close arbitrary results or captures. Resource cleanup comes from `with` or an acquisition-specific delivery contract. See [completion and acquisition](runtime.md#completion-and-resource-acquisition).

The optional named `timeout` argument shortens the inherited deadline; it never waives joining. See [timeouts](cancellation.md#timeouts). Callbacks and results are ordinary values; no sharing bound or callable proof is required. Use [Synchronized](../standard-library/data-and-io/synchronized-state.md#synchronized) when callbacks must coordinate a complete read/modify/write update. The [standard API contract](../standard-library/types/prelude.md#joined-concurrency) fixes the callable/result mapping and legal uses of inferred packs; general source declaration syntax for packs is unsupported.
