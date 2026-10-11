+++
title = "Assertions and programming faults"
weight = 30
+++

# Assertions and programming faults

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A programming fault signals a broken invariant. Expected bad inputs should be validated with control flow and represented by [Result](results.md) when the caller needs a failure value.

## Assertions

`assert condition` checks a programming invariant and produces a fault when false.

The condition must have type `Bool` and is evaluated once. `assert` is a statement, not a value-producing expression; numeric or text conditions are rejected.

```text
fn discount_validated(price: Decimal, percent: Decimal) -> Decimal:
    assert price > 0d
    assert percent > 0d
    assert percent < 100d
    return price * (1d - percent / 100d)
```

This example expects strictly positive prices and percentages below 100 as preconditions. A violation is treated as a programming fault. Use the validating `discount` function in [expected failures](results.md) when these values come from ordinary runtime input.

## Explicit faults

An explicit `panic(message: message)` produces a programming fault when code determines that an invariant has failed.

Its source type is `fn(message: String) -> Never`. It never completes normally; a call can appear where any expression result type is expected, including an `Int` return position. This does not create a catchable expected-error value or permit normal fallthrough in a non-`Unit` function. See [Unit, Never, and return completeness](../functions/declarations-and-calls.md#unit-and-never).

```text
panic(message: "Required invariant was violated.")
```

A fault aborts the current operation after cleanup. Programming faults are distinct from expected `Result` errors.

## Cleanup and observation

Cleanup still runs after a fault. A cleanup fault can replace a pending return, domain error, or cancellation, while secondary faults are retained as diagnostics. The full selection and cleanup rules are in [lexical cleanup](../../ownership-and-cleanup/cleanup/_index.md).

An active `parallel` caller observes an operation fault as `ExecutionError.Crashed` after siblings are cancelled and joined. Background faults go to the service's failure observer. A caller's own fault still unwinds it; [try](propagation.md) only propagates `Result` errors. See [execution errors](../../concurrency/joining.md).

[Previous: Error propagation with try](propagation.md)
