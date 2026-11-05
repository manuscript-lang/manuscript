+++
title = "Error propagation with try"
weight = 2
+++

# Error propagation with try

`try expression` unwraps `ok`; on `error` it returns that error from the enclosing function, which must return a compatible `Result`.

Save the `discount.ms` module from [expected failures](results.md#returning-a-domain-error), then save this program beside it as `discount-label.ms`. Run `ms run discount-label.ms`; it prints `Discounted price: 18`:

<!-- manuscript-example: {"mode":"run","stdout":"Discounted price: 18\n","build_files":{"discount.ms":"import Decimal from \"@std/math/decimal.ms\"\n\nexport enum DiscountError:\n    InvalidPrice\n    InvalidPercent\n\nexport fn discount(price: Decimal, percent: Decimal) Decimal!DiscountError:\n    if price < 0d:\n        return error(InvalidPrice)\n    if percent < 0d or percent > 100d:\n        return error(InvalidPercent)\n\n    return ok(price * (1d - percent / 100d))"}} -->
```manuscript
import Decimal from "@std/math/decimal.ms"
import DiscountError, discount from "./discount.ms"

fn discounted_label(price: Decimal, percent: Decimal) String!DiscountError:
    let value = try discount(price, percent)
    return ok("Discounted price: {value}")

export fn main() Int:
    let outcome = discounted_label(20d, 10d)
    if let value = outcome:
        print(value)
        return 0
    print(outcome.err())
    return 1
```

Read this as two paths through one function. A successful discount continues to build the label. A failed discount leaves immediately, before interpolation runs; the caller receives the same domain error. `try` is useful precisely when this function has no better recovery decision to make.

## Success and failure paths

On `ok`, `value` holds the `Decimal`. On `error`, the function returns that error immediately. Success types may differ (decimal versus text); the error type is forwarded unchanged.

`Result[Unit, E]` can be propagated as a statement. Save this complete test as `ready_test.ms` and run `ms test ready_test.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn prepare() Unit!: ok(unit)

fn ready_label() String!:
    try prepare()
    return ok("ready")

test "prepare before returning a label":
    try expect_equal(try ready_label(), "ready")
```

```text
RUN ready_test.ms::prepare before returning a label
PASS ready_test.ms::prepare before returning a label
1 tests, 0 failed
```

Standalone `try call()` requires a `Unit` success. Otherwise bind it (`let name = try call()`) or `return try call()`.

Omitting `try` discards the Result, which the checker rejects. Return it, propagate it, or handle both outcomes. The reference describes [explicit discard syntax](results.md#discarding-a-result), which deliberately loses the outcome rather than handling it.

## Try in a pipe flow

`| try step` in a [pipe flow](../basics/expressions.md#pipe-flows) applies these rules to that step. This complete version uses a formatting function after the discount. Save as `discount-pipe.ms` beside `discount.ms` and run `ms run discount-pipe.ms`; it also prints `Discounted price: 18`:

<!-- manuscript-example: {"mode":"run","stdout":"Discounted price: 18\n","build_files":{"discount.ms":"import Decimal from \"@std/math/decimal.ms\"\n\nexport enum DiscountError:\n    InvalidPrice\n    InvalidPercent\n\nexport fn discount(price: Decimal, percent: Decimal) Decimal!DiscountError:\n    if price < 0d:\n        return error(InvalidPrice)\n    if percent < 0d or percent > 100d:\n        return error(InvalidPercent)\n\n    return ok(price * (1d - percent / 100d))"}} -->
```manuscript
import Decimal from "@std/math/decimal.ms"
import DiscountError, discount from "./discount.ms"

fn label(value: Decimal) String:
    return "Discounted price: {value}"

fn discounted_label(price: Decimal, percent: Decimal) String!DiscountError:
    return ok(try discount(price, percent) | label)

export fn main() Int:
    let outcome = discounted_label(20d, 10d)
    if let value = outcome:
        print(value)
        return 0
    print(outcome.err())
    return 1
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
