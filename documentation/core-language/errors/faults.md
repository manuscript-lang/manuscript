+++
title = "Programming faults"
weight = 3
+++

# Programming faults

A programming fault means an assumption the code relies on has failed. For invalid user input, return a [Result](results.md) error instead.

## Invariant checks

Check an invariant with `if` and `return`; import `panic` from `@std/faults.ms` to raise a fault when it fails.

```manuscript
import panic from "@std/faults.ms"

fn discount_validated(price: Decimal, percent: Decimal) Decimal:
    if price <= 0d:
        return panic("Price must be positive")
    if percent <= 0d or percent >= 100d:
        return panic("Percent must be positive and below 100")
    return price * (1d - percent / 100d)
```

The example treats nonpositive prices and percentages outside (0, 100) as faults. For runtime input, use the validating `discount` in [expected failures](results.md).

## Explicit faults

`panic(message: message)` raises a programming fault. Its type is `fn(message: String) Never`: it never completes normally and fits any result type, but it is not a catchable error and does not permit fallthrough in a non-`Unit` function. See [Unit and Never](../functions/declarations-and-calls.md#unit-and-never).

```manuscript
panic("Required invariant was violated.")
```

A fault aborts the current operation after cleanup.

## Runaway recursion

- Source calls may nest 200,000 deep. Past that, the fault is `call depth limit exceeded (200000 nested calls)`, with the innermost source frames. It unwinds, runs cleanup, and fails only the current test.
- A fault trace keeps its innermost 32 frames.
- `==` and `!=` recurse through nested values; past 250,000 the fault is `equality depth limit exceeded (250000 nested values)`.

## Cleanup and observation

Cleanup runs after a fault. A cleanup fault can replace a pending return, domain error, or cancellation; secondary faults are kept as diagnostics. See [lexical cleanup](../cleanup/_index.md).

A TaskGroup or failed Task join observes an operation fault as `ExecutionError.Crashed` after siblings are cancelled and joined. Scheduler faults go to the service's failure observer. [try](propagation.md) propagates only `Result` errors, never faults.
