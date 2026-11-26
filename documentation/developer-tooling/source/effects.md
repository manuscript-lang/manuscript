+++
title = "Understanding effects"
weight = 3
+++

# Understanding effects

This page covers the call-graph view of how code reads and writes data. For permissions that `ms check --only lint` enforces, see [effects and permissions](../../core-language/functions/effects.md).

Use the effects view when you review how code reads or changes data and reaches external operations. It follows calls, so you can see how a small helper reaches behavior outside the program.

Save this as `hello.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Manuscript!\n"} -->
```manuscript
fn main() Void {
    print("Hello, Manuscript!")
}
```

`ms run hello.ms` prints `Hello, Manuscript!`. To inspect its calls without running it:

```sh
ms map hello.ms --view effects --entity main
```

```text
EFFECTS VIEW
`- main  effects: std.console.write
   `- @std/core.ms::print
```

The summary lists the declared effects reachable through `print`, not just statements written directly in `main`. These are the same names `ms check --only lint` checks against `allow_effect`. A function that reaches none is pure. Use the call path to find the implementation you need to review. For a larger program, open an [interactive code map](../implementation.md#interactive-code-map) or use the [review report](../implementation.md#review-report) to find newly introduced effects.

## Transitive analysis

Effects combine along calls: a function reaches the union of the declared effects (`// ms: effect NAME`) of everything it calls.

| Call target | How it contributes to the summary |
| --- | --- |
| Source function | Include its effects, including the effects of its callees. |
| Several possible targets | Include the union of their effects. |
| Standard-library function with a declared effect | Include that effect (`std.fs.read`, `std.console.write`). |

Summaries describe reachable behavior. To restrict what a function may reach, use [effects and permissions](../../core-language/functions/effects.md); this view does not enforce anything.

## Effects and cancellation

Cancellation cannot undo an external write that has already completed. Before retrying an operation, check both the errors it returned and the external effects it may already have had.
