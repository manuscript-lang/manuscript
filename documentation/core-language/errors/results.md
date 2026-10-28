+++
title = "Expected failures with Result"
weight = 1
+++

# Expected failures with Result

Use `Result[T, E]` when an operation succeeds with `T` or fails with an expected error `E`. `E` must implement `Error`, so `Result[Int, String]` is rejected; wrap text as `TextError("message")` or declare a domain error with `impl Error`. `Result`, `ok`, and `error` are in the prelude.

Return `ok(value: ...)` for success and `error(cause: ...)` for failure. Both are ordinary values. A caller can test it with `is_error()`, read the success path with `if let`, or pass the error back with `try`. Validate runtime input with ordinary conditions before doing the work.

## Returning a domain error

```manuscript
type DiscountError:
    case InvalidPrice
    case InvalidPercent

impl Error for DiscountError:
    fn message() String:
        match self:
            InvalidPrice: return "invalid price"
            InvalidPercent: return "invalid percent"

fn discount(price: Decimal, percent: Decimal) Result[Decimal, DiscountError]:
    if price < 0d:
        return error(InvalidPrice)
    if percent < 0d or percent > 100d:
        return error(InvalidPercent)

    return ok(price * (1d - percent / 100d))
```

The function validates inputs, returns an explicit error for each failure, and wraps the result in `ok`.

## Handling the result

This continues the declarations above:

```manuscript
fn discount_message(price: Decimal, percent: Decimal) String:
    if let value = discount(price, percent):
        return "Discounted price: {value}"
    return "Discount could not be calculated."
```

This caller discards the cause. To use it, call `err()` after `is_error()`, or [propagate it with try](propagation.md).

## Checking, extracting, and composing

| Method | Behavior |
| --- | --- |
| `is_ok()`, `is_error()` | Test the case, including successful zero, false, or Unit values |
| `get(default: Optional[T] = none) T` | Return the successful payload, or `default` on an error; without a default, [fault](faults.md) on an error |
| `err() E` | Return the error payload; fault on success |
| `get_or_else(create: fn(E) T) T` | Return the successful payload, or call `create` once with the original error on failure |
| `or_else(create: fn(E) Result[T, E]) Result[T, E]` | Keep a success, or call `create` once with the original error and return its Result |
| `map_error[F: Error](transform: fn(E) F) Result[T, F]` | Transform an error once; preserve a success unchanged |
| `map[U](transform: fn(T) U) Result[U, E]` | Transform success once; preserve an error unchanged |
| `and_then[U](transform: fn(T) Result[U, E]) Result[U, E]` | On success, return the callback's Result; preserve an existing error |

`map` wraps the callback's value in `ok`, even if it is a Result or Optional. `and_then` requires the same `E`; translate unrelated errors with ordinary functions.

This fragment uses `discount` above:

```manuscript
let price = discount(price: 20d, percent: 10d).get(0d)
let text = discount(price: 20d, percent: 10d).map(fn value: value.to_string())
```

Callbacks run sequentially in the caller's context; faults and cancellation propagate normally. `get` reports `called Result.get() on error`; use it only when success is established. Routine failures use a fallback, `if let`, or `try`.

## Converting success to an Optional

`to_optional() Optional[T]` returns `some` with the original payload, or `none` on error. It does not clone or flatten the payload, and does not turn faults or cancellation into absence.

```manuscript
import TextError from "@std/core.ms"
fn successful_price(outcome: Result[Decimal, TextError]) Optional[Decimal]:
    return outcome.to_optional()
```

To turn absence into an error, use [Optional.ok_or or ok_or_else](../types/optionals.md#converting-absence-to-a-result).

## Discarding a result

A standalone call such as `discount(price: 20d, percent: 10d)` discards both outcomes, and the checker rejects it, including for `Result[Unit, E]`. Handle it with `if let`, `try`, or return it. To ignore it deliberately, bind it to `_`:

```manuscript
let _ = discount(price: 20d, percent: 10d)
```

The initializer still runs and the outcome is dropped unread. Several `let _` may share a scope. This does not handle an error or stop a fault.

## A common error boundary

Usually keep the concrete domain error type. To accept several error types, use the prelude `Error` interface (`message() String`). Standard errors implement it; custom errors declare `impl Error`.

```manuscript
import Bytes from "@std/bytes.ms"
import hex_decode from "@std/encoding.ms"

fn decode(text: String) Result[Bytes, Error]:
    let bytes = try hex_decode(text)
    return ok(bytes)
```

`try` passes the original `EncodingError` into the `Error` boundary. Callers use `cause.message()` or recover the type with a [contract type pattern](../control-flow/pattern-matching.md#contract-type-patterns). A caller needing only encoding errors can keep `Result[Bytes, EncodingError]`.

An `Error` implementer can be passed, assigned, or returned where `Error` is expected, and `Result[T, SpecificError]` can be returned as `Result[T, Error]` with payloads preserved. See [error compatibility](propagation.md#error-compatibility).

Use [Optional](../types/optionals.md) for absence and [faults](faults.md) for broken invariants.
