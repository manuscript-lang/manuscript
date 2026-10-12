+++
title = "Expected failures with Result"
weight = 1
+++

# Expected failures with Result

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

For most functions, keep the concrete domain error type. Its typed fields are available directly to callers; see [error details](../../standard-library/contracts.md#error-details).

When a boundary should accept several error types, import `Error` from `@std/errors.ms`. It is an ordinary interface declaring `message() -> String`. Standard errors implement it; custom errors can declare an `impl Error` in their defining module.

```manuscript
import Bytes from "@std/bytes.ms"
import Error from "@std/errors.ms"
import hex_decode from "@std/encoding.ms"
import Result from "@std/result.ms"

fn decode(text: String) -> Result[Bytes, Error]:
    let bytes = try hex_decode(text: text)
    return ok(value: bytes)
```

`try` passes the original `EncodingError` into the common Error boundary. A caller may handle it with `cause.message()`, or recover its specific type and fields using a [contract type pattern](../control-flow/pattern-matching.md#contract-type-patterns). A caller that needs only encoding errors can keep `Result[Bytes, EncodingError]` and match its cases directly.

An error implementing `Error` can be passed, assigned, or returned directly wherever `Error` is expected. `Result[T, SpecificError]` can also be returned as `Result[T, Error]`; its successful value and original error are preserved. Other error values remain legal in `Result[T, E]`. See [error compatibility](propagation.md#error-compatibility) for propagation rules.

## Results and concurrent execution

Returning `error(cause: cause)` is normal function completion. In a TaskGroup, the domain Result remains the operation's return value and does not cancel siblings. Task.join separately reports ExecutionError; see [task groups](../../concurrency/task-groups.md). A [Scheduler](../../concurrency/scheduling.md) service reports completion-only domain errors through its configured failure observer.

Use [Optional](../types/optionals.md) for absence without an error explanation and [explicit faults](faults.md) for broken programming invariants.
