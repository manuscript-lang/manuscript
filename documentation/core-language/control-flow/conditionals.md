+++
title = "Conditionals"
weight = 1
+++

# Conditionals

Use `if` to run a block when a Boolean condition is true. Add `else` to run a different block when it is false. Only the selected branch runs.

```manuscript
fn status(active: Bool) -> String:
    if active:
        return "Active"
    else:
        return "Inactive"
```

A short branch can use one simple statement on the same line:

```manuscript
fn status(active: Bool) -> String:
    if active: return "Active"
    else: return "Inactive"
```

See the [suite rules](../basics/grammar.md#statements-and-patterns) for mixing inline and indented bodies.

Conditions require `Bool`. The condition in this example is already a Boolean; numeric and text values do not acquire truth values implicitly.

`if` is a statement and does not produce a value. Evaluate its condition once; execute exactly one selected branch, or neither branch when the condition is false and no `else` is present. `else` and `else if` start on separate lines, aligned with the corresponding `if`. An additional conditional uses `else if`, not `elif`.

Each branch has its own lexical scope. Names declared in a branch are not visible after the conditional; assignments to an outer `var` affect that existing binding. An `else if` chain checks conditions in order and stops after selecting a branch.

```manuscript
fn classify(value: Int) -> String:
    if value < 0:
        return "negative"
    else if value == 0:
        return "zero"
    else:
        return "positive"
```

`if 1:` is rejected because its condition is `Int`. `let result = if active: ...` is rejected because `if` is not an expression. Use branch-local assignment to a declared `var` or explicit returns to select a result. The [function return rules](../functions/declarations-and-calls.md#unit-and-never) determine whether all reachable paths return.

## Unwrapping an Optional or Result

`if let name = expression:` runs its block only when an [Optional](../types/optionals.md) holds a value or a [Result](../errors/results.md) is `ok`, and binds `name` to that value inside the block. The expression evaluates once. An `else` block runs when the Optional is `none` or the Result is an error, and `name` is not visible there or after the conditional. A Result's error is not captured; use `match` or `try` when the error matters. The binding is immutable and `expression` must be an `Optional` or `Result`; a `Bool` condition is rejected.

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

A present payload such as `0`, `false`, or an empty string still takes the first branch. The binding takes one name; destructure the payload inside the block. Prefer `if let` to a two-arm `match` on `some` and `none`, which `ms lint` reports as **MSL108**.

## Validating inputs

Validation uses the same ordinary control flow as any other decision:

```manuscript
fn nonnegative(value: Int) -> Bool:
    if value < 0:
        return false

    return true
```

The early `return` exits the function on the negative path. The final return runs on the remaining path. [Expected failures](../errors/results.md) uses this structure to reject invalid input with a domain error.

## Bindings after a branch

Every binding is initialized at declaration. To select a value for use after the conditional, initialize an outer `var` and assign to it in the branches. Branch-local names stay inside their branch. See [bindings](../basics/bindings.md).

Use [pattern matching](pattern-matching.md) when the decision depends on which case of an alternative value is present.
