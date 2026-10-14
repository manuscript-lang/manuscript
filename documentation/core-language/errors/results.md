+++
title = "Expected failures with Result"
weight = 1
+++

# Expected failures with Result

Use `Result[T, E]` when an operation can either succeed with a value of type `T` or fail with an expected error of type `E`. `Result`, `ok`, and `error` are available from the prelude without imports.

Return `ok(value: ...)` for success and `error(cause: ...)` for failure. Both are ordinary values. A caller can inspect the result with `match` or pass the error back with `try`. Validate runtime input with ordinary conditions before doing the work.

## Returning a domain error

```manuscript
type DiscountError:
    case InvalidPrice
    case InvalidPercent

fn discount(price: Decimal, percent: Decimal) -> Result[Decimal, DiscountError]:
    if price < 0d:
        return error(InvalidPrice)
    if percent < 0d or percent > 100d:
        return error(InvalidPercent)

    return ok(price * (1d - percent / 100d))
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

## Checking, extracting, and composing

| Method | Behavior |
| --- | --- |
| `is_ok()`, `is_error()` | Test the case, including successful zero, false, or Unit values |
| `unwrap() -> T` | Return the successful payload; [fault](faults.md) on an error |
| `unwrap_error() -> E` | Return the error payload; fault on success |
| `unwrap_or(fallback: T) -> T` | Return success or the eagerly evaluated fallback |
| `unwrap_or_else(create: fn(cause: E) -> T) -> T` | Call `create` once with the original error only on failure |
| `map[U](transform: fn(value: T) -> U) -> Result[U, E]` | Transform success once; preserve an error unchanged |
| `and_then[U](transform: fn(value: T) -> Result[U, E]) -> Result[U, E]` | On success, return the callback's Result; preserve an existing error |

`E` can be any value type; it does not need to implement Error. Extraction and composition retain payload references. `map` wraps the callback's value in `ok`, even when that value is another Result or Optional. `and_then` requires the same error type `E`. Translate unrelated errors with ordinary functions and matching.

This fragment uses `discount` above:

```manuscript
let price = discount(price: 20d, percent: 10d).unwrap_or(0d)
let text = discount(price: 20d, percent: 10d).map(fn(value): value.toString())
```

Callbacks run sequentially in the caller's execution context. Their faults and cancellation propagate normally. `unwrap` reports `called Result.unwrap() on error`; use it only when success is established or failure is a programming error. Routine expected failures use a fallback, matching, or `try`.

## Converting success to an Optional

`to_optional() -> Optional[T]` returns `some` with the original successful payload, or `none` for an error. It neither clones nor flattens the payload, invokes error operations, or turns faults and cancellation into absence.

```manuscript
fn successful_price(outcome: Result[Decimal, String]) -> Optional[Decimal]:
    return outcome.to_optional()
```

To turn absence into an error, use [Optional.ok_or or ok_or_else](../types/optionals.md#converting-absence-to-a-result).

## Discarding a result

A standalone call such as `discount(price: 20d, percent: 10d)` evaluates the
operation but discards both success and failure. `ms lint` reports advisory
`MSL104` for a discarded `Result`, including `Result[Unit, E]`. Checking still
accepts the statement. Handle the result with `match`, propagate it with `try`,
or return it to the caller.

When ignoring both outcomes is deliberate, use a named binding beginning with
`_`, such as this fragment using `discount` above:

```manuscript
let _ignored = discount(price: 20d, percent: 10d)
```

The initializer still runs, and the `_ignored` name suppresses the unread-local
advisory. This does not handle an error or stop a programming fault.

## A common error boundary

For most functions, keep the concrete domain error type. Its typed fields are available directly to callers; see [error details](../../standard-library/contracts.md#error-details).

When a boundary should accept several error types, use the prelude `Error` interface without an import. It is an ordinary interface declaring `message() -> String`. Standard errors implement it; custom errors can declare an `impl Error` in their defining module.

```manuscript
import Bytes from "@std/bytes.ms"
import hex_decode from "@std/encoding.ms"

fn decode(text: String) -> Result[Bytes, Error]:
    let bytes = try hex_decode(text: text)
    return ok(bytes)
```

`try` passes the original `EncodingError` into the common Error boundary. A caller may handle it with `cause.message()`, or recover its specific type and fields using a [contract type pattern](../control-flow/pattern-matching.md#contract-type-patterns). A caller that needs only encoding errors can keep `Result[Bytes, EncodingError]` and match its cases directly.

An error implementing `Error` can be passed, assigned, or returned directly wherever `Error` is expected. `Result[T, SpecificError]` can also be returned as `Result[T, Error]`; its successful value and original error are preserved. Other error values remain legal in `Result[T, E]`. See [error compatibility](propagation.md#error-compatibility) for propagation rules.

## Results and concurrent execution

Returning `error(cause: cause)` is normal function completion. In a TaskGroup, the domain Result remains the operation's return value and does not cancel siblings. Task.join separately reports ExecutionError; see [task groups](../../concurrency/task-groups.md). A [Scheduler](../../concurrency/scheduling.md) service reports completion-only domain errors through its configured failure observer.

Use [Optional](../types/optionals.md) for absence without an error explanation and [explicit faults](faults.md) for broken programming invariants.
