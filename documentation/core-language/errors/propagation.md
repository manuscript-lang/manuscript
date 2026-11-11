+++
title = "Error propagation with ?"
weight = 2
+++

# Error propagation with ?

A postfix `expression?` unwraps `ok`; on `error` it returns that error from the enclosing function, which must return a compatible `Result`. It reads after the call, so nested calls and pipe steps need no leading keyword.

The following continues the `discount` and `DiscountError` declarations in [expected failures](results.md):

```manuscript
fn discounted_label(price: Decimal, percent: Decimal) Result[String, DiscountError]:
    value := discount(price, percent)?
    return ok("Discounted price: {value}")
```

## Reading `?` next to `?.`

- `?` can exit the function; `?.` never does. `a?.b` is [optional chaining](../types/optionals.md) on an Optional.
- `?` applies to a Result only. For an Optional, use `if x := v:` or `v.get(default)`.
- `load()?.name` is rejected: `?.` chains an Optional and `load()` returns a Result. Bind first: `u := load()?`, then `u.name`.
- `?` does not repeat: `f()??` is rejected.
- `place[key]?` is the in-place borrow in an `if var` head, not propagation.

## Success and failure paths

On `ok`, `value` holds the `Decimal`. On `error`, the function returns that error immediately. Success types may differ (decimal versus text); the error type is forwarded unchanged.

`Result[Unit, E]` can be propagated as a statement. Save this complete test as `ready_test.ms` and run `ms test ready_test.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

fn prepare() Unit!: ok(unit)

fn ready_label() String!:
    prepare()?
    return ok("ready")

test "prepare before returning a label":
    expect_equal(ready_label()?, "ready")?
```

```text
RUN ready_test.ms::prepare before returning a label
PASS ready_test.ms::prepare before returning a label
1 tests, 0 failed
```

Standalone `call()?` requires a `Unit` success. Otherwise bind it (`name := call()?`) or `return call()?`.

Omitting `?` discards the Result, which the checker rejects. To ignore it deliberately, use [`_ :=`](results.md#discarding-a-result).

## Propagation in a pipe flow

A trailing `?` on a pipe step in a [pipe flow](../basics/expressions.md#pipe-flows) applies these rules to that step. Given `fn label(value: Decimal) String`, this equals `value := discount(...)?` then `label(value)`:

```manuscript
fn discounted_label(price: Decimal, percent: Decimal) Result[String, DiscountError]:
    return ok(discount(price, percent)? | label)
```

## Error compatibility

`?` requires the operand's error type to be the enclosing function's error type.

- `Result[T, E]` can become `Result[U, E]` for the same `E`. `Error` has no special conversion: it is an ordinary type.
- The original error and its fields pass through unchanged.
- Different error types need an explicit translation, for example [`map_error`](results.md#converting-a-domain-error-to-error) or [pattern matching](../control-flow/pattern-matching.md).
- The operand is evaluated once. `operation()? + 1` means `(operation()?) + 1`.
- Inside an anonymous function, `?` returns from that function.

The compiler rejects `?` when:

- its expression is not a Result;
- its error type differs from the function's;
- the enclosing function or test returns Unit.

See [type compatibility](../types/compatibility.md).

## Cleanup and cancellation

`?` does not catch faults or parent cancellation. A propagated error is a return path and performs [lexical cleanup](../cleanup/_index.md) for scopes it leaves.
