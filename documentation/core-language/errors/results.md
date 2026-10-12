+++
title = "Expected failures with Result"
weight = 28
+++

# Expected failures with Result

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use `Result[T, E]` when an operation can either succeed with a value of type `T` or fail with an expected error of type `E`. Import `Result` from `@std/result.ms`.

Return `ok(value: ...)` for success and `error(cause: ...)` for failure. Both are ordinary values. A caller can inspect the result with `match` or pass the error back with `try`. Validate runtime input with ordinary conditions before doing the work.

## Returning a domain error

```manuscript
type DiscountError:
    case InvalidPrice
    case InvalidPercent

fn discount(price: Decimal, percent: Decimal) -> Result[Decimal, DiscountError]:
    if price < 0d:
        return error(cause: InvalidPrice)
    if percent < 0d or percent > 100d:
        return error(cause: InvalidPercent)

    return ok(value: price * (1d - percent / 100d))
```

The function checks inputs before calculating. It returns an explicit error for each invalid condition and wraps the calculated decimal in `ok` on success.

## Handling the result

The following continues the declarations above:

```manuscript
fn discount_message(price: Decimal, percent: Decimal) -> String:
    let outcome = discount(price: price, percent: percent)
    match outcome:
        ok(value):
            return "Discounted price: {value}"
        error(cause):
            return "Discount could not be calculated."
```

This caller chooses a response for either outcome. Another caller could inspect `cause` with a further match or [propagate it with try](propagation.md).

## A common error boundary

Import `Error` from `@std/errors.ms` when a boundary should accept multiple error domains. It is an ordinary interface declaring `message() -> String`. Standard errors implement it; user errors can declare an ordinary `impl Error` in their defining module.

```text
import Bytes from "@std/bytes.ms"
import Error from "@std/errors.ms"
import hex_decode from "@std/encoding.ms"
import Result from "@std/result.ms"

fn decode(text: String) -> Result[Bytes, Error]:
    match hex_decode(text: text, max_bytes: some(value: 1024)):
        ok(value):
            return ok(value: value)
        error(cause):
            return error(cause: Error(value: cause))
```

The conversion preserves the original `EncodingError` case and payload. A caller may handle any error with `cause.message()`, or select a specific implementation using a [contract type pattern](../control-flow/pattern-matching.md#contract-type-patterns). A caller that needs only encoding errors can keep `Result[Bytes, EncodingError]` and match its cases directly.

`Error` is explicitly imported and has no special inheritance or exception machinery. Other error values remain legal in `Result[T, E]`. Conversion at a generic boundary is explicit, and `try` still requires the [same error type](propagation.md#error-compatibility).

## Results and concurrent execution

Returning `error(cause: cause)` is normal function completion. In a TaskGroup, the domain Result remains the operation's return value and does not cancel siblings. Task.join separately reports ExecutionError; see [task groups](../../concurrency/task-groups.md). A [Scheduler](../../standard-library/tasks/scheduler.md) service reports completion-only domain errors through its configured failure observer.

Use [Optional](../types/optionals.md) for absence without an error explanation and [explicit faults](faults.md) for broken programming invariants.

[Previous: Pattern matching](../control-flow/pattern-matching.md) · [Next: Error propagation with try](propagation.md)
