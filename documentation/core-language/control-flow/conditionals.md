+++
title = "Conditionals"
weight = 1
+++

# Conditionals

`if` runs a block when a `Bool` condition is true; `else` runs otherwise.

```manuscript
fn status(active: Bool) -> String:
    if active:
        return "Active"
    else:
        return "Inactive"
```

A short branch can be one simple statement on the same line:

```manuscript
fn status(active: Bool) -> String:
    if active: return "Active"
    else: return "Inactive"
```

See the [suite rules](../basics/grammar.md#statements-and-patterns) for mixing inline and indented bodies.

- Conditions must be `Bool`; numbers and text have no truth values.
- `if` is a statement, not an expression.
- The condition is evaluated once; at most one branch runs.
- `else` and `else if` start on their own line, aligned with `if`. There is no `elif`.
- Each branch has its own scope; assignments to an outer `var` persist.
- An `else if` chain tests in order and stops at the first match.

```manuscript
fn classify(value: Int) -> String:
    if value < 0:
        return "negative"
    else if value == 0:
        return "zero"
    else:
        return "positive"
```

`if 1:` and `let result = if active: ...` are rejected. Select a result with an assigned `var` or explicit returns; the [return rules](../functions/declarations-and-calls.md#unit-and-never) require every reachable path to return.

## Unwrapping an Optional or Result

`if let name = expression:` runs its block when an [Optional](../types/optionals.md) holds a value or a [Result](../errors/results.md) is `ok`, binding `name` immutably inside the block. `else` runs for `none` or an error, where `name` is not visible. A Result's error is not captured; use `try` or `unwrap_error()` when it matters. The expression evaluates once and must be an `Optional` or `Result`.

```manuscript
fn greeting(name: Optional[String]) -> String:
    if let value = name:
        return "Hello, " + value
    else:
        return "Hello!"
```

```manuscript
fn port(lookup: Result[Int, String]) -> Int:
    if let value = lookup:
        return value
    return 8080
```

A present `0`, `false`, or empty string still takes the first branch. The binding is one name; destructure inside the block. Prefer `if let` to a two-arm `match` on `some`/`none` (**MSL108**).

## Validating inputs

Validate with an early return:

```manuscript
fn nonnegative(value: Int) -> Bool:
    if value < 0:
        return false

    return true
```

[Expected failures](../errors/results.md) uses this shape to reject invalid input with a domain error.

## Bindings after a branch

To select a value for use after the conditional, initialize an outer `var` and assign it in the branches. See [bindings](../basics/bindings.md). Use [pattern matching](pattern-matching.md) to branch on the case of an alternative.
