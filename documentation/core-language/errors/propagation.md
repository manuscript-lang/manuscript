+++
title = "Error propagation with ?"
weight = 2
+++

# Error propagation with ?

A postfix `expression?` unwraps `ok`; on `error` it returns that error from the enclosing function, which must return a compatible `Result`. Because it is written after the call, nested calls and pipe steps need no leading keyword.

The following continues the `discount` and `DiscountError` declarations in [expected failures](results.md):

<!-- manuscript-example: {"mode":"fragment","context":"import Decimal from \"@std/math/decimal.ms\"\n\ntype DiscountError {\n    reason String\n}\n\nfn discount(price Decimal, percent Decimal) Result[Decimal, DiscountError] {\n    return ok(price)\n}","given":[]} -->
```manuscript
fn discounted_label(price, percent Decimal) Result[String, DiscountError] {
    value := discount(price, percent)?
    return ok(f"Discounted price: {value}")
}
```

## `?` on Results and Optionals

- `?` applies to a Result or an Optional. On a Result it returns the error; on an [Optional](../types/optionals.md#unwrapping-with-) it returns `null` (or just returns, from a `Void` function) when the value is absent.
- A function cannot mix the two: a Result needs a Result return, an Optional needs an Optional or `Void` return.
- `load()?.name` is `(load()?).name`: unwrap, then read `name`. There is no `?.` operator.
- `?` does not repeat: `f()??` is rejected.
- `place[key]?` is the in-place borrow in an `if var` head, not propagation.

## Success and failure paths

On `ok`, `value` holds the `Decimal`. On `error`, the function returns that error immediately. Success types may differ (decimal versus text); the error type is forwarded unchanged.

`Result[Void, E]` can be propagated as a statement. Save this complete test as `ready_test.ms` and run `ms test ready_test.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn prepare() Void! => ok()

fn ready_label() String! {
    prepare()?
    return ok("ready")
}

test "prepare before returning a label" {
    expect_equal(ready_label()?, "ready")?
}
```

```text
RUN ready_test.ms::prepare before returning a label
PASS ready_test.ms::prepare before returning a label
1 tests, 0 failed
```

Standalone `call()?` requires a `Void` success. Otherwise bind it (`name := call()?`) or `return call()?`.

Omitting `?` discards the Result, which the checker rejects. To ignore it deliberately, use [`void`](results.md#discarding-a-result).

## Propagation in a pipe flow

A trailing `?` on a pipe step in a [pipe flow](../basics/expressions.md#pipe-flows) applies these rules to that step. Given `fn label(value Decimal) String`, this equals `value := discount(...)?` then `label(value)`:

<!-- manuscript-example: {"mode":"fragment","context":"import Decimal from \"@std/math/decimal.ms\"\n\ntype DiscountError {\n    reason String\n}\n\nfn discount(price Decimal, percent Decimal) Result[Decimal, DiscountError] {\n    return ok(price)\n}\n\nfn label(value Decimal) String {\n    return value.to_string()\n}","given":[]} -->
```manuscript
fn discounted_label(price, percent Decimal) Result[String, DiscountError] {
    return ok(discount(price, percent)? | label)
}
```

## Error compatibility

`?` requires the operand's error type to be the enclosing function's error type.

- `Result[T, E]` can become `Result[U, E]` for the same `E`. `Error` has no special conversion: it is an ordinary type.
- The original error and its fields pass through unchanged.
- Different error types need an explicit translation, for example [`map_error`](results.md#converting-a-domain-error-to-error) or [pattern matching](../control-flow/pattern-matching.md).
- The operand is evaluated once. `operation()? + 1` means `(operation()?) + 1`.
- Inside an anonymous function, `?` returns from that function.

The compiler rejects `?` when:

- its expression is not a Result or an Optional;
- its error type differs from the function's;
- the enclosing function or test returns Void and the operand is a Result (a `Void` function may use `?` on an Optional);
- the operand is an Optional and the function returns neither an Optional nor `Void` (a test returns a Result, so `?` in a test applies to Results only).

See [type compatibility](../types/compatibility.md).

## Cleanup and cancellation

`?` does not catch faults or parent cancellation. A propagated error is a return path and performs [lexical cleanup](../cleanup/_index.md) for scopes it leaves.
