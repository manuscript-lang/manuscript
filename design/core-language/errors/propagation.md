+++
title = "Error propagation with try"
weight = 29
+++

# Error propagation with try

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use `try` when a function should return an expected error from a called operation instead of handling it locally.

`try expression` unwraps `ok`; on `error`, it returns that error from the enclosing function. The function must return a compatible `Result`.

The following continues the `discount` and `DiscountError` declarations in [expected failures](results.md):

```text
fn discounted_label(price: Decimal, percent: Decimal) -> Result[String, DiscountError]:
    let value = try discount(price: price, percent: percent)
    return ok(value: "Discounted price: {value}")
```

## Success and failure paths

When `discount` returns `ok`, `value` contains the `Decimal` payload and the function builds its label. When it returns `error`, the enclosing function returns that error instead of executing the remaining statements.

The success types differ: the called function returns a decimal, while the enclosing function returns text. Both use `DiscountError`, so the error can be forwarded unchanged.

## Error compatibility

Error conversion uses the standard `map_error(result: outcome, transform: fn(cause: E) -> F)` adapter or an explicit match; its exact signature and single-evaluation rule are in the [standard API contract](../../standard-library/types/prelude.md). A caller with a different error contract must translate the error explicitly. `try` does not invent a conversion or combine unrelated error types into an implicit union.

Precisely, an operand `Result[T, E]` has success type `T`, and the enclosing function must return `Result[U, E]` with the same exact error type `E`. Its success type `U` may differ. Merely implementing a common contract does not make two error types compatible; explicit contract conversion must occur before building the operand result.

The operand evaluates once. Prefix `try` binds more tightly than arithmetic, so `try operation() + 1` means `(try operation()) + 1`. An operand that is not a `Result`, a mismatched error type, or `try` inside a `Unit` function or `Unit` test body is rejected. For an anonymous function, the enclosing function is that anonymous function, not its caller or containing body. See [expressions](../basics/expressions.md) and [type compatibility](../types/compatibility.md).

## Cleanup and cancellation

`try` does not catch programming faults or parent cancellation. A propagated error is a return path and performs [lexical cleanup](../../ownership-and-cleanup/cleanup/_index.md) for the scopes it leaves. A [programming fault](faults.md) or [parent cancellation](../../concurrency/cancellation.md) follows its own unwinding rules.

[Previous: Expected failures with Result](results.md) · [Next: Assertions and programming faults](faults.md)
