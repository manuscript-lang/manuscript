+++
title = "Error propagation with try"
weight = 2
+++

# Error propagation with try

`try expression` unwraps `ok`; on `error` it returns that error from the enclosing function, which must return a compatible `Result`.

The following continues the `discount` and `DiscountError` declarations in [expected failures](results.md):

```manuscript
fn discounted_label(price: Decimal, percent: Decimal) Result[String, DiscountError]:
    let value = try discount(price, percent)
    return ok("Discounted price: {value}")
```

## Success and failure paths

On `ok`, `value` holds the `Decimal`. On `error`, the function returns that error immediately. Success types may differ (decimal versus text); the error type is forwarded unchanged.

`Result[Unit, E]` can be propagated as a statement:

```manuscript
fn prepare() Unit!: ok(unit)

fn ready_label() String!:
    try prepare()
    return ok("ready")
```

Standalone `try call()` requires a `Unit` success. Otherwise bind it (`let name = try call()`) or `return try call()`.

Omitting `try` discards the Result, which the checker rejects. To ignore it deliberately, use [`let _ =`](results.md#discarding-a-result).

## Try in a pipe flow

`| try step` in a [pipe flow](../basics/expressions.md#pipe-flows) applies these rules to that step. Given `fn label(value: Decimal) String`, this equals `let value = try discount(...)` then `label(value)`:

```manuscript
fn discounted_label(price: Decimal, percent: Decimal) Result[String, DiscountError]:
    return ok(try discount(price, percent) | label)
```

## Error compatibility

`try` requires the operand's error type to be the enclosing function's error type.

- `Result[T, E]` can become `Result[U, E]` for the same `E`. `Error` has no special conversion: it is an ordinary record.
- The original error and its fields pass through unchanged.
- Different error types need an explicit translation, for example [`map_error`](results.md#converting-a-domain-error-to-error) or [pattern matching](../control-flow/pattern-matching.md).
- The expression after `try` is evaluated once. `try operation() + 1` means `(try operation()) + 1`.
- Inside an anonymous function, `try` returns from that function.

The compiler rejects `try` when:

- its expression is not a Result;
- its error type differs from the function's;
- the enclosing function or test returns Unit.

See [type compatibility](../types/compatibility.md).

## Cleanup and cancellation

`try` does not catch faults or parent cancellation. A propagated error is a return path and performs [lexical cleanup](../cleanup/_index.md) for scopes it leaves.
