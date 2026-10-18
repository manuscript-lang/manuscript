+++
title = "Loops"
weight = 2
+++

# Loops

`for` / `in` visits collection values; `while` repeats while a `Bool` condition holds. `break` ends the loop; `continue` starts the next iteration. Loops are statements: no labels, result values, range syntax, or custom iteration protocol.

## Traversing a list

```manuscript
fn sum(values: List[Int]) Int:
    var total = 0
    for value in values:
        total += value

    return total
```

## Counting loops

`range(start, end)` from `@std/collections.ms` includes `start`, excludes `end`, and counts up by one. A `for` over a direct `range` call is a counter loop that allocates no list.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import range from "@std/collections.ms"
import panic from "@std/faults.ms"

test "sum indexes":
    var total = 0
    for index in range(0, 5):
        total += index
    if total != 10:
        return panic("Expected 10, got {total}")
```

`end <= start` visits nothing. Bounds are evaluated once, in order, before the first iteration. As a plain value, `range(0, count)` is a `List[Int]`; over 268,435,456 items faults, so use `range_by(max_items:)` for larger lists.

Use `while` with a counter for other steps or computed exits:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/faults.ms"

test "five iterations":
    var index = 0
    var total = 0
    while index < 5:
        total += index
        index += 1
    if index != 5 or total != 10:
        return panic("Expected five iterations and total 10")
```

Increment the counter before any `continue` that would skip its update.

## Stepped ranges

`range_by(start, end, step, max_items)` returns `Result[List[Int], CollectionError]`. Negative steps count down: `range_by(start: 5, end: 0, step: -2)` is `[5, 3, 1]`. Equal endpoints or a step away from the end give an empty list. `step: 0` is `InvalidInput`; exceeding `max_items` is `LimitExceeded`. Unwrap the Result before looping:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import range_by from "@std/collections.ms"
import expect_equal from "@std/testing.ms"

test "sum even indexes":
    let indexes = try range_by(start: 0, end: 6, step: 2)
    var total = 0
    for index in indexes:
        total += index
    try expect_equal(total, 6)
```

`try` unwraps the range in a function or test whose error type is compatible; `get([])` supplies a fallback. `for index in 0..5:` is unsupported. See the [range declarations](../../standard-library/reference/collections.md#range).

## Iterable types and binding

The iterable is evaluated once. A List traversal keeps its original slice and length without copying: later element writes are visible, appends are not. Map and Set snapshot their membership. The loop variable is one immutable name per iteration, with no pattern or annotation. Supported iterables:

| Iterable | Iteration binding type | Traversal order |
| --- | --- | --- |
| `List[T]` | `T` | Position order |
| `Set[T]` | `T` | Insertion order |
| `Map[K, V]` | `MapEntry[K, V]` | Key insertion order |

`MapEntry[K, V]` is a record with `key: K` and `value: V` (constructor from `@std/collections.ms`; iteration needs no import). It is not a positional pair; destructure it in the body.

```manuscript
fn total(values: Map[String, Int]) Int:
    var sum = 0
    for entry in values:
        let {key, value} = entry
        sum += value
    return sum
```

`for [key, value] in values:` is a parse error. Numbers, text, optionals, functions, and objects with a `next` method are not iterable. Each iteration has a new scope; assigning to the loop variable is rejected, but an outer `var` can change.

## Repeating while a condition holds

```manuscript
fn count_down(start: Int) Int:
    var remaining = start
    while remaining > 0:
        remaining -= 1

    return remaining
```

`while` re-tests its condition before every iteration, including after `continue`. An empty iterable or initially false condition runs no body.

## Exiting an iteration

`break` and `continue` target the nearest enclosing loop in the same function body, take no labels or arguments, and are rejected outside a loop; an anonymous function cannot break its enclosing loop. `return` exits the function.

Each of the three runs cleanup for the scopes it exits. Each iteration is its own scope, so `with` resources close when the iteration ends; a plain `let` registers no cleanup. See [lexical cleanup](../cleanup/_index.md).

## Cancellation

Each loop back-edge is a cancellation checkpoint, so CPU-bound loops respond to cancellation without explicit calls.
