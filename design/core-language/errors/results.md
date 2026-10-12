+++
title = "Expected failures with Result"
weight = 28
+++

# Expected failures with Result

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use `Result[T, E]` when an operation can either succeed with a value of type `T` or fail with an expected error of type `E`. Import `Result` from `@std/result.ms`; import its `map_error` helper separately if you use it.

Return `ok(value: ...)` for success and `error(cause: ...)` for failure. Both are ordinary values. A caller can inspect the result with `match` or pass the error back with `try`. Validate runtime input with ordinary conditions before doing the work.

## Returning a domain error

```text
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

```text
fn discount_message(price: Decimal, percent: Decimal) -> String:
    let outcome = discount(price: price, percent: percent)
    match outcome:
        ok(value):
            return "Discounted price: {value}"
        error(cause):
            return "Discount could not be calculated."
```

This caller chooses a response for either outcome. Another caller could inspect `cause` with a further match or [propagate it with try](propagation.md).

## Results and concurrent execution

Returning `error(cause: cause)` is normal function completion. In `parallel`, the domain `Result` remains the operation's return value and does not cancel siblings. The outer API result separately reports `ExecutionError`; see [parallel operations](../../concurrency/parallel.md). A [Background](../../standard-library/tasks/background.md) service reports completion-only domain errors through its configured failure observer.

Use [Optional](../types/optionals.md) for absence without an error explanation and [explicit faults](faults.md) for broken programming invariants.

[Previous: Pattern matching](../control-flow/pattern-matching.md) · [Next: Error propagation with try](propagation.md)
