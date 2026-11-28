+++
title = "Programming faults"
weight = 3
+++

# Programming faults

A programming fault means an assumption the code relies on has been broken. For invalid user input, return a [Result](results.md) error instead. [Choosing a failure](_index.md#choosing-a-failure-in-the-standard-library) lists which cause gets which result.

## Invariant checks

Check an invariant with `if` and `return`; import `panic` from `@std/core.ms` to raise a fault when it fails.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import (
    panic from "@std/core.ms",
    Decimal from "@std/math/decimal.ms",
)

fn discount_validated(price, percent Decimal) Decimal {
    if price <= 0d {
        return panic("Price must be positive")
    }
    if percent <= 0d or percent >= 100d {
        return panic("Percent must be positive and below 100")
    }

    return price * (1d - percent / 100d)
}
```

The example treats nonpositive prices and percentages outside (0, 100) as faults. For runtime input, use the validating `discount` in [expected failures](results.md).

## Explicit faults

`panic(message)` raises a programming fault. Its type is `fn(String) Never`: it never completes normally, so it fits any result type. It is not a catchable error, and it does not let control fall off the end of a function that does not return `Void` or `Void!`. See [Void and Never](../functions/declarations-and-calls.md#void-and-never).

<!-- manuscript-example: {"mode":"fragment","given":[]} -->
```manuscript
import panic from "@std/core.ms"
panic("Required invariant was violated.")
```

A fault aborts the current operation, after running cleanup.

## Faults the checker rejects

When constant operands make a fault certain, `ms check` reports an error instead of leaving it for run time:

- Integer `+ - * / %` over literals whose result leaves the operand type's range (`9223372036854775807 + 1`).
- Integer `/` or `%` by a constant zero (`n / 0`, `n % (2 - 2)`).
- A constant index outside a list literal (`[1, 2][2]`; negative indexes count from the end, so `[1, 2][-3]` is outside too).

Only literals and arithmetic over literals are folded. Values that arrive through bindings, parameters, or calls are checked at run time. To demonstrate a fault in a test, make the operand a runtime value.

## Runaway recursion

- Recursion is limited by stack size, not by a call count. A program and each of its tasks may use up to 256 MiB of stack, so small frames allow millions of nested calls. The task of a promise starts on 512 KiB, which keeps a million parked promises within a few gigabytes, and grows in 512 KiB steps as a recursion needs them.
  - When the stack runs out, the fault is `stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the recursion for a missing base case, or iterate instead`, with the innermost source frames.
  - It unwinds and runs cleanup. In a test run, it fails the current test while other tests remain isolated.
- `ms check --only lint` reports **MSL112** for a function that calls itself on every path, such as `fn f(n Int) Int => f(n - 1)`; a `return`, `?`, or fault before the call counts as a base case.
- A fault trace keeps its innermost 32 frames.
- `==` and `!=` recurse through nested values and stop after 256 levels, answering unequal. They do not fault for depth. A cycle compares unequal.

## Out of memory

When the system refuses an allocation, the fault is `out of memory: could not allocate N bytes; hold less data at once, or process it in chunks or as a stream`. Like any fault it reports source frames and runs cleanup, then exits with status 139. A program that the operating system kills for lack of memory after overcommit never reaches this report.

## Exit status

A fault reports, runs cleanup, then ends the process the way a C program ends: status 134 (what a shell reports for `abort`, 128 plus SIGABRT), or 139 (SIGSEGV) for a stack overflow or out of memory. The numbers are the same on every platform. The process exits normally after the report, so no core dump or crash dialog appears. `main` may return only 0 to 125, so a fault status never collides with a program's own.

## Cleanup and observation

Cleanup runs after a fault. A cleanup fault can replace a pending return, domain error, or cancellation; secondary faults are kept as diagnostics. See [lexical cleanup](../cleanup/_index.md).

[?](propagation.md) propagates only `Result` errors, never faults.
