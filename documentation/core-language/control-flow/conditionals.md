+++
title = "Conditionals"
weight = 1
+++

# Conditionals

`if` runs a block when a `Bool` condition is true; `else` runs otherwise.

```manuscript
fn status(active: Bool) String:
    if active:
        return "Active"
    else:
        return "Inactive"
```

A short branch can be one simple statement on the same line:

```manuscript
fn status(active: Bool) String:
    if active: return "Active"
    else: return "Inactive"
```

See the [suite rules](../basics/grammar.md#statements-and-patterns) for mixing inline and indented bodies.

- Conditions must be `Bool`; numbers and text have no truth values.
- `if` is a statement here; the expression form is [below](#if-as-an-expression).
- The condition is evaluated once; at most one branch runs.
- `else if` and `else` start on their own line, aligned with `if`.
- Each branch has its own scope; assignments to an outer `var` persist.
- An `else if` chain tests in order and stops at the first match.

```manuscript
fn classify(value: Int) String:
    if value < 0:
        return "negative"
    else if value == 0:
        return "zero"
    else:
        return "positive"
```

`if 1:` is rejected: the condition must be `Bool`.

## If as an expression

`if c: a else: b` is an expression when it appears where a value is expected. Both branches are single expressions of one type, `else` is required, and `else if` chains:

```manuscript
fn sign(value: Int) Int:
    return if value < 0: -1 else if value == 0: 0 else: 1
```

The branches are one-line expressions on the same line. For statements in a branch, use an `if` statement or a `match` arm. The [return rules](../functions/declarations-and-calls.md#unit-and-never) still require every reachable path of a function to return.

## Unwrapping an Optional or Result

`if let name = expression:` runs its block when an [Optional](../types/optionals.md) holds a value or a [Result](../errors/results.md) is `ok`, binding `name` immutably inside the block. `else` runs for `none` or an error, where `name` is not visible. A Result's error is not captured; use `try` or `err()` when it matters. The expression evaluates once and must be an `Optional` or `Result`.

```manuscript
fn greeting(name: String?) String:
    if let value = name:
        return "Hello, " + value
    else:
        return "Hello!"
```

```manuscript
import TextError from "@std/core.ms"
fn port(lookup: Result[Int, TextError]) Int:
    if let value = lookup:
        return value
    return 8080
```

`if var name = place[key]?:` borrows a map or list entry in place. `place[key]?` is the entry when it exists, and `name` is a mutable borrow of it: `if var entry = entries[key]?:` then `entry.count = entry.count + 1` changes the value in `entries`, and `if var n = counts[key]?: n += 1` updates `counts` without copying a scalar. A missing key or out-of-range index takes the `else` branch. The origin must be `var`, and nothing else may use it until the last use of `name`. `place[key]?` is written only here. `if var name = expression:` on any other value binds an owned copy of the payload.

A present `0`, `false`, or empty string still takes the first branch. The binding is one name; destructure inside the block. Prefer `if let` to a two-arm `match` on a payload name and `none` (**MSL108**).

## Validating inputs

Validate with an early return:

```manuscript
fn nonnegative(value: Int) Bool:
    if value < 0:
        return false

    return true
```

[Expected failures](../errors/results.md) uses this shape to reject invalid input with a domain error.

## Bindings after a branch

To select a value for use after the conditional, initialize an outer `var` and assign it in the branches. See [bindings](../basics/bindings.md). Use [pattern matching](pattern-matching.md) to branch on the case of an alternative.
