+++
title = "Error propagation with try"
weight = 2
+++

# Error propagation with try

`try expression` unwraps `ok`; on `error` it returns that error from the enclosing function, which must return a compatible `Result`.

The following continues the `discount` and `DiscountError` declarations in [expected failures](results.md):

```manuscript
fn discounted_label(price: Decimal, percent: Decimal) -> Result[String, DiscountError]:
    let value = try discount(price, percent)
    return ok("Discounted price: {value}")
```

## Success and failure paths

On `ok`, `value` holds the `Decimal`. On `error`, the function returns that error immediately. Success types may differ (decimal versus text); the error type is forwarded unchanged.

`Result[Unit, E]` can be propagated as a statement:

```manuscript
fn prepare() -> Result[Unit, String]: ok(unit)

fn ready_label() -> Result[String, String]:
    try prepare()
    return ok("ready")
```

Standalone `try call()` requires a `Unit` success. Otherwise bind it (`let name = try call()`) or `return try call()`.

Omitting `try` discards the Result and triggers lint `MSL104`. To ignore it deliberately, use an [`_ignored` binding](results.md#discarding-a-result).

## Try in a pipe flow

`| try step` in a [pipe flow](../basics/expressions.md#pipe-flows) applies these rules to that step. Given `fn label(value: Decimal) -> String`, this equals `let value = try discount(...)` then `label(value)`:

```manuscript
fn discounted_label(price: Decimal, percent: Decimal) -> Result[String, DiscountError]:
    return ok(try discount(price, percent) | label)
```

## Error compatibility

`try` accepts the enclosing function's error type, or a specific error implementing `Error` when the function returns `Result[U, Error]`.

- `Result[T, E]` can become `Result[U, E]`; or `Result[U, Error]` if `E` implements `Error`.
- The original error, concrete type, and fields pass through unchanged.
- An explicit `impl Error` establishes the relationship; matching method names do not. See [common error boundaries](results.md#a-common-error-boundary).
- Unrelated error types need explicit translation with [pattern matching](../control-flow/pattern-matching.md). An `Error` cannot narrow without a type match.
- The expression after `try` is evaluated once. `try operation() + 1` means `(try operation()) + 1`.
- Inside an anonymous function, `try` returns from that function.

The compiler rejects `try` when:

- its expression is not a Result;
- its error type differs from the function's and cannot pass into its `Error` boundary;
- the enclosing function or test returns Unit.

See [type compatibility](../types/compatibility.md).

## Cleanup and cancellation

`try` does not catch faults or parent cancellation. A propagated error is a return path and performs [lexical cleanup](../cleanup/_index.md) for scopes it leaves.
