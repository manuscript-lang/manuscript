+++
title = "Expected failures with Result"
weight = 1
+++

# Expected failures with Result

Use `Result[T, E]` when an operation succeeds with `T` or fails with an expected error `E`. `E` may be any value type. Most failures use the prelude record [`Error`](#the-error-record). `Result`, `ok`, `error`, and `Error` are in the prelude.

Return `ok(value: ...)` for success and `error(cause: ...)` for failure. Both are ordinary values. A caller can test it with `is_error()`, read the success path with `if let`, or pass the error back with `try`. Validate runtime input with ordinary conditions before doing the work.

## Shorthand: `T!` and `T!E`

`T!` is `Result[T, Error]` and `T!E` (with no space before `E`) is `Result[T, E]`, mirroring `T?` for optionals. Use `T!E` for a failure that is not an `Error`. `Result[T, E]` stays valid.

```manuscript
fn parse_port(text: String) Int!:
    let port = try text.parse_int().ok_or()
    return ok(port)
```

Suffixes apply left to right: `Int?!` is `Result[Int?, Error]` and `Int!?` is `Optional[Result[Int, Error]]`. A function type needs parentheses first, as with `?`: `(fn() Int)!`.

## The Error record

`Error` is a plain record with a fixed shape, in the style of Go's `errors.New`:

```manuscript
export type Error:
    message: String
    kind: ErrorCategory = ErrorCategory.Other
    details: Map[String, String] = Map[String, String]()
```

- `message` is the text to show a person.
- `kind` is an `ErrorCategory` a caller can branch on: `InvalidInput`, `InvalidData`, `LimitExceeded`, `NotFound`, `AlreadyExists`, `PermissionDenied`, `Unsupported`, `Closed`, `Timeout`, `Unavailable`, `OutOfRange`, `Failed`, or `Other` (the default).
- `details` holds extra named context as text, such as a path or a line number.

Build one with the record call. There is no separate constructor and no namespace.

```manuscript
fn find_user(id: Int) String!:
    if id < 0:
        return error(Error("negative id", kind: ErrorCategory.InvalidInput))
    return error(Error("no such user", kind: ErrorCategory.NotFound, details: {"id": id.to_string()}))

fn describe(id: Int) String:
    let outcome = find_user(id)
    if outcome.is_ok(): return outcome.get()
    if outcome.err().kind == ErrorCategory.NotFound: return "missing {outcome.err().details["id"]}"
    return outcome.err().message.clone()
```

Standard-library failures are `Error` values too: branch on `kind`, read `details`, and do not import a per-module error type. Two errors are equal when their three fields are equal.

## Returning a domain error

An `Error` fits most code. Use your own type as `E` when callers need typed payloads or exhaustive cases.

```manuscript
import Decimal from "@std/math/decimal.ms"

type DiscountError:
    case InvalidPrice
    case InvalidPercent

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
| `get(default: T?) T` | Return the successful payload, or `default` on an error; without a default, [fault](faults.md) on an error |
| `err() E` | Return the error payload; fault on success |
| `get_or_else(create: fn(E) T) T` | Return the successful payload, or call `create` once with the original error on failure |
| `or_else(create: fn(E) Result[T, E]) Result[T, E]` | Keep a success, or call `create` once with the original error and return its Result |
| `map_error[F](transform: fn(E) F) Result[T, F]` | Transform an error once; preserve a success unchanged |
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

`to_optional() T?` returns the original payload as a present optional, or `none` on error. It does not clone or flatten the payload, and does not turn faults or cancellation into absence.

```manuscript
fn successful_price(outcome: Result[Decimal, Error]) Decimal?:
    return outcome.to_optional()
```

To turn absence into an error, use [Optional.ok_or or ok_or_else](../types/optionals.md#converting-absence-to-a-result).

## Discarding a result

A standalone call such as `discount(price: 20d, percent: 10d)` discards both outcomes, and the checker rejects it, including for `Result[Unit, E]`. Handle it with `if let`, `try`, or return it. To ignore it deliberately, bind it to `_`:

```manuscript
let _ = discount(price: 20d, percent: 10d)
```

The initializer still runs and the outcome is dropped unread. Several `let _` may share a scope. This does not handle an error or stop a fault.

## Converting a domain error to Error

`try` forwards the error type unchanged and never converts one. Translate a domain error with an ordinary function or `map_error`:

```manuscript
fn discount_error(cause: DiscountError) Error:
    return Error("discount failed", kind: ErrorCategory.InvalidInput)

fn discount_checked(price: Decimal, percent: Decimal) Decimal!:
    return discount(price, percent).map_error(discount_error)
```

Use [Optional](../types/optionals.md) for absence and [faults](faults.md) for broken invariants.
