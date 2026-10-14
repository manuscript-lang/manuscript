+++
title = "Programming faults"
weight = 3
+++

# Programming faults

A programming fault means an assumption the code relies on has failed. Use ordinary conditional returns to check that assumption. For ordinary invalid user input, use conditions and return a [Result](results.md) error so the caller can respond.

## Invariant checks

Use ordinary `if` and `return` control flow to check an invariant. Import `panic` from `@std/faults.ms` when a violated invariant must produce a programming fault.

```manuscript
import panic from "@std/faults.ms"

fn discount_validated(price: Decimal, percent: Decimal) -> Decimal:
    if price <= 0d:
        return panic(message: "Price must be positive")
    if percent <= 0d or percent >= 100d:
        return panic(message: "Percent must be positive and below 100")
    return price * (1d - percent / 100d)
```

This example expects strictly positive prices and percentages below 100 as preconditions. A violation is treated as a programming fault. Use the validating `discount` function in [expected failures](results.md) when these values come from ordinary runtime input.

## Explicit faults

An explicit `panic(message: message)` produces a programming fault when code determines that an invariant has failed.

Its source type is `fn(message: String) -> Never`. It never completes normally; a call can appear where any expression result type is expected, including an `Int` return position. This does not create a catchable expected-error value or permit normal fallthrough in a non-`Unit` function. See [Unit, Never, and return completeness](../functions/declarations-and-calls.md#unit-and-never).

```manuscript
panic(message: "Required invariant was violated.")
```

A fault aborts the current operation after cleanup. Programming faults are distinct from expected `Result` errors.

## Runaway recursion

Source calls may nest 200,000 deep. A call past that limit is a programming fault, `call depth limit exceeded (200000 nested calls)`, with the source frames of the innermost calls and a note that outer frames are omitted. It unwinds, runs cleanup, and fails a test like any other fault, so the rest of a test run continues. Any fault trace keeps only its innermost 32 frames. Comparing values with `==` or `!=` recurses through nested records, alternatives, and collections; past 250,000 nested values the comparison is the fault `equality depth limit exceeded (250000 nested values)`, so a very long linked structure cannot crash the process.

## Cleanup and observation

Cleanup still runs after a fault. A cleanup fault can replace a pending return, domain error, or cancellation, while secondary faults are retained as diagnostics. The full selection and cleanup rules are in [lexical cleanup](../cleanup/_index.md).

A TaskGroup or failed Task join observes an operation fault as `ExecutionError.Crashed` after siblings are cancelled and joined. Scheduler faults go to the service's failure observer. A caller's own fault still unwinds it; [try](propagation.md) only propagates `Result` errors. See [execution errors](../../concurrency/joining.md).
