+++
title = "Error propagation with try"
weight = 2
+++

# Error propagation with try

Use `try` to continue with a successful Result value or immediately return its error to your caller. This is useful when the current function cannot handle the expected failure itself.

`try expression` unwraps `ok`; on `error`, it returns that error from the enclosing function. The function must return a compatible `Result`.

The following continues the `discount` and `DiscountError` declarations in [expected failures](results.md):

```manuscript
fn discounted_label(price: Decimal, percent: Decimal) -> Result[String, DiscountError]:
    let value = try discount(price: price, percent: percent)
    return ok("Discounted price: {value}")
```

## Success and failure paths

When `discount` returns `ok`, `value` contains the `Decimal` payload and the function builds its label. When it returns `error`, the enclosing function returns that error instead of executing the remaining statements.

The success types differ: the called function returns a decimal, while the enclosing function returns text. Both use `DiscountError`, so the error can be forwarded unchanged.

A call returning `Result[Unit, E]` can be propagated as a statement, without a throwaway binding:

```manuscript
fn prepare() -> Result[Unit, String]: ok(unit)

fn ready_label() -> Result[String, String]:
    try prepare()
    return ok("ready")
```

Standalone `try call()` requires a `Unit` success value. For other success types, bind the value with `let name = try call()` or return it with `return try call()`; it cannot be silently discarded.

Omitting `try` discards the entire Result, including any error, and produces the
`MSL104` lint advisory. To deliberately ignore both outcomes, use an explicit
[`_ignored` binding](results.md#discarding-a-result).

## Try in a pipe flow

A sequence of steps can read as one flow with [pipe steps](../basics/expressions.md#pipe-flows). `| try step` applies this page's rules to that step's result. Given `fn label(value: Decimal) -> String`, the following equals `let value = try discount(...)` followed by `label(value)`:

```manuscript
fn discounted_label(price: Decimal, percent: Decimal) -> Result[String, DiscountError]:
    return ok(try discount(price: price, percent: percent) | label)
```

## Error compatibility

`try` accepts the same error type as the enclosing function, or a specific error implementing the common `Error` interface when the enclosing function returns `Result[U, Error]`.

Keep a chain of fallible calls flat with `try` when their error boundaries are compatible. Translate unrelated domain errors explicitly when needed.

If the called operation returns `Result[T, E]`, the enclosing function can return `Result[U, E]`. If `E` implements `Error`, it can instead return `Result[U, Error]`. The success type may change from `T` to `U`. The original error, its concrete type, and its fields pass through unchanged; no cause wrapper or manual unwrapping is needed.

This common boundary also accepts direct assignments, arguments, and returns of a specific error, and forwarding `Result[T, E]` as `Result[T, Error]` with the same success type. An explicit `impl Error` establishes the relationship; matching method names alone do not. See [common error boundaries](results.md#a-common-error-boundary).

Unrelated domain error types still require explicit translation: test `is_error()`, convert `unwrap_error()`, and return the new `error(...)`. An Error value cannot narrow to a specific domain error without a [contract type pattern](../control-flow/pattern-matching.md#contract-type-patterns). Other interfaces, collection types, and function types keep their ordinary exact compatibility rules.

The expression after `try` is evaluated once. Try binds more tightly than arithmetic, so `try operation() + 1` means `(try operation()) + 1`.

The compiler rejects try when:

- its expression is not a Result;
- its error type differs from the enclosing function's error type and cannot pass into its Error boundary;
- the enclosing function or test returns Unit.

Inside an anonymous function, try returns from that anonymous function, not from its caller or surrounding function. See [expressions](../basics/expressions.md) and [type compatibility](../types/compatibility.md).

## Cleanup and cancellation

`try` does not catch programming faults or parent cancellation. A propagated error is a return path and performs [lexical cleanup](../cleanup/_index.md) for the scopes it leaves. A [programming fault](faults.md) or [parent cancellation](../../concurrency/cancellation.md) follows its own unwinding rules.
