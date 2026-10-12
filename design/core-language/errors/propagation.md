+++
title = "Error propagation with try"
weight = 29
+++

# Error propagation with try

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use `try` to continue with a successful Result value or immediately return its error to your caller. This is useful when the current function cannot handle the expected failure itself.

`try expression` unwraps `ok`; on `error`, it returns that error from the enclosing function. The function must return a compatible `Result`.

The following continues the `discount` and `DiscountError` declarations in [expected failures](results.md):

```manuscript
fn discounted_label(price: Decimal, percent: Decimal) -> Result[String, DiscountError]:
    let value = try discount(price: price, percent: percent)
    return ok(value: "Discounted price: {value}")
```

## Success and failure paths

When `discount` returns `ok`, `value` contains the `Decimal` payload and the function builds its label. When it returns `error`, the enclosing function returns that error instead of executing the remaining statements.

The success types differ: the called function returns a decimal, while the enclosing function returns text. Both use `DiscountError`, so the error can be forwarded unchanged.

## Error compatibility

A caller with a different error contract must translate the error explicitly using [pattern matching](../control-flow/pattern-matching.md). `try` does not invent a conversion or combine unrelated error types into an implicit union.

If the called operation returns `Result[T, E]`, the function using `try` must return `Result[U, E]`. The success type may change from `T` to `U`, but the error type `E` must be exactly the same. Two error types are not interchangeable just because they implement the same interface. Convert explicitly before constructing the Result that try uses.

The expression after `try` is evaluated once. Try binds more tightly than arithmetic, so `try operation() + 1` means `(try operation()) + 1`.

The compiler rejects try when:

- its expression is not a Result;
- its error type differs from the enclosing function's error type;
- the enclosing function or test returns Unit.

Inside an anonymous function, try returns from that anonymous function, not from its caller or surrounding function. See [expressions](../basics/expressions.md) and [type compatibility](../types/compatibility.md).

## Cleanup and cancellation

`try` does not catch programming faults or parent cancellation. A propagated error is a return path and performs [lexical cleanup](../../ownership-and-cleanup/cleanup/_index.md) for the scopes it leaves. A [programming fault](faults.md) or [parent cancellation](../../concurrency/cancellation.md) follows its own unwinding rules.

[Previous: Expected failures with Result](results.md) · [Next: Programming faults](faults.md)
