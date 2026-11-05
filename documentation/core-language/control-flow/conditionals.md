+++
title = "Conditionals"
weight = 1
+++

# Conditionals

`if` runs a block when a `Bool` condition is true; `else` runs otherwise.

Save this as `status.ms` and run `ms run status.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Active\nInactive\n"} -->
```manuscript
fn status(active: Bool) String:
    if active:
        return "Active"
    else:
        return "Inactive"

export fn main() Int:
    print(status(true))
    print(status(false))
    return 0
```

```text
Active
Inactive
```

A short branch can be one simple statement on the same line:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Active\nInactive\n"} -->
```manuscript
fn status(active: Bool) String:
    if active: return "Active"
    else: return "Inactive"

export fn main() Int:
    print(status(true))
    print(status(false))
    return 0
```

```text
Active
Inactive
```

See the [suite rules](../basics/grammar.md#statements-and-patterns) for mixing inline and indented bodies.

- Conditions must be `Bool`; numbers and text have no truth values.
- `if` is a statement here; the expression form is [below](#if-as-an-expression).
- The condition is evaluated once; at most one branch runs.
- `else if` and `else` start on their own line, aligned with `if`.
- Each branch has its own scope; assignments to an outer `var` persist.
- An `else if` chain tests in order and stops at the first match.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"negative\nzero\npositive\n"} -->
```manuscript
fn classify(value: Int) String:
    if value < 0:
        return "negative"
    else if value == 0:
        return "zero"
    else:
        return "positive"

export fn main() Int:
    print(classify(-1))
    print(classify(0))
    print(classify(1))
    return 0
```

```text
negative
zero
positive
```

`if 1:` is rejected: the condition must be `Bool`.

## If as an expression

`if c: a else: b` is an expression when it appears where a value is expected. Both branches are single expressions of one type, `else` is required, and `else if` chains:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"-1\n0\n1\n"} -->
```manuscript
fn sign(value: Int) Int:
    return if value < 0: -1 else if value == 0: 0 else: 1

export fn main() Int:
    print(sign(-4))
    print(sign(0))
    print(sign(9))
    return 0
```

```text
-1
0
1
```

The branches are one-line expressions on the same line. For statements in a branch, use an `if` statement or a `match` arm. The [return rules](../functions/declarations-and-calls.md#unit-and-never) still require every reachable path of a function to return.

## Unwrapping an Optional or Result

`if let name = expression:` runs its block when an [Optional](../types/optionals.md) holds a value or a [Result](../errors/results.md) is `ok`, binding `name` immutably inside the block. `else` runs for `none` or an error, where `name` is not visible. A Result's error is not captured; use `try` or `err()` when it matters. The expression evaluates once and must be an `Optional` or `Result`.

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"Hello, Ada\nHello!\n"} -->
```manuscript
fn greeting(name: String?) String:
    if let value = name:
        return "Hello, " + value
    else:
        return "Hello!"

export fn main() Int:
    print(greeting("Ada"))
    print(greeting())
    return 0
```

```text
Hello, Ada
Hello!
```

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"8080\nport must be between 1 and 65535\nconfiguration missing\n"} -->
```manuscript
fn port(lookup: Int!) Int!:
    if let value = lookup:
        if value > 0 and value <= 65535:
            return ok(value)
        return error(Error("port must be between 1 and 65535"))
    return error(lookup.err())

fn show_port(lookup: Int!) Unit:
    let outcome = port(lookup)
    if let value = outcome:
        print(value)
        return
    print(outcome.err().message)

export fn main() Int:
    show_port(ok(8080))
    show_port(ok(0))
    show_port(error(Error("configuration missing")))
    return 0
```

```text
8080
port must be between 1 and 65535
configuration missing
```

The success branch validates the port. If the lookup failed, the final return preserves its cause instead of silently replacing it with a default port. `err()` is reached only after the success branch has returned. Use `try` when you simply want to propagate failure before continuing a longer calculation.

`if var name = place[key]?:` borrows a map or list entry in place. `place[key]?` is the entry when it exists, and `name` is a mutable borrow of it: `if var entry = entries[key]?:` then `entry.count = entry.count + 1` changes the value in `entries`, and `if var n = counts[key]?: n += 1` updates `counts` without copying a scalar. A missing key or out-of-range index takes the `else` branch. The origin must be `var`, and nothing else may use it until the last use of `name`. `place[key]?` is written only here. `if var name = map.get(key):` also borrows the map entry in place. For other expressions, `if var` can take an owned payload (including from a local at its last use), but cannot mutably borrow an arbitrary Optional. To change an independent copy, use `if let` and explicitly clone the payload into a `var`.

This complete test updates an existing map entry:

Save this test as `example.ms` and run `ms test example.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import expect_equal from "@std/test/test.ms"

test "increment a visit count":
    var counts = {"visits": 2}
    if var count = counts.get("visits"):
        count += 1
    try expect_equal(counts.get("visits").get(0), 3)
```

```text
RUN example.ms::increment a visit count
PASS example.ms::increment a visit count
1 tests, 0 failed
```

A present `0`, `false`, or empty string still takes the first branch. The binding is one name; destructure inside the block. Prefer `if let` to a two-arm `match` on a payload name and `none` (**MSL108**).

## Validating inputs

Validate with an early return:

Save this complete example as `example.ms` and run `ms run example.ms`:

<!-- manuscript-example: {"mode":"run","stdout":"false\ntrue\n"} -->
```manuscript
fn nonnegative(value: Int) Bool:
    if value < 0:
        return false

    return true

export fn main() Int:
    print(nonnegative(-1))
    print(nonnegative(0))
    return 0
```

```text
false
true
```

[Expected failures](../errors/results.md) uses this shape to reject invalid input with a domain error.

## Bindings after a branch

To select a value for use after the conditional, initialize an outer `var` and assign it in the branches. See [bindings](../basics/bindings.md). Use [pattern matching](pattern-matching.md) to branch on the case of an enum.
