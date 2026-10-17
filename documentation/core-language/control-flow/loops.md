+++
title = "Loops"
weight = 2
+++

# Loops

Use `for` / `in` to visit the values in a collection. Use `while` to repeat work while a Boolean condition is true. Inside either loop, `break` ends the loop and `continue` moves to the next iteration.

Loops are statements, not expressions. Manuscript has no labeled loops, loop-result values, integer-range syntax, or user-defined iteration protocol.

## Traversing a list

```manuscript
fn sum(values: List[Int]) -> Int:
    var total = 0
    for value in values:
        total += value

    return total
```

The list contains integers. Each iteration binds an element and updates the accumulator. Addition uses checked `Int` arithmetic, so overflow is a [programming fault](../errors/faults.md).

## Counting loops

Import `range` from `@std/collections.ms` to count. `range(start, end)` includes `start`, excludes `end`, and counts up by one. A `for` over a direct `range` call runs as a counter loop: it allocates no list, so the bound can be large.

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

`end <= start` visits nothing. Both bounds are evaluated once, in written order, before the first iteration; assigning to a variable used as a bound inside the body does not change the count. `range(0, count)` as an ordinary value is a `List[Int]`; more than 268,435,456 items is a fault, so size larger lists with `range_by(max_items:)`.

Use `while` with a counter when the step is not one or the loop must stop early on a computed condition:

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

`range_by(start, end, step, max_items)` takes an explicit nonzero step and returns `Result[List[Int], CollectionError]`. A positive step moves upward; a negative step moves downward. `range_by(start: 5, end: 0, step: -2)` produces `[5, 3, 1]`. Equal endpoints or a step directed away from the end produce an empty list. `step: 0` returns `InvalidInput`; `max_items` bounds allocation and returns `LimitExceeded` when exceeded. A `Result` is not iterable, so unwrap it before the loop:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import range_by from "@std/collections.ms"
import panic from "@std/faults.ms"

test "sum even indexes":
    match range_by(start: 0, end: 6, step: 2):
        ok(indexes):
            var total = 0
            for index in indexes:
                total += index
            if total != 6:
                return panic("Expected 6, got {total}")
        error(cause):
            return panic("Could not build range: {cause.message()}")
```

In a function returning a compatible `Result`, `let indexes = try range_by(start: 0, end: 6, step: 2)` is another way to unwrap. `for index in 0..5:` is unsupported. See the [range declarations](../../standard-library/reference/collections.md#range).

## Iterable types and binding

Evaluate a `for`'s iterable expression once before entering the loop. A List traversal captures its backing slice and initial length without copying: later element writes can be observed, append does not extend the traversal, and reallocation leaves it reading the original array. Map and Set snapshot their membership. Referenced elements remain shared. The loop introduces one immutable identifier per iteration; it does not accept a binding pattern or a type annotation. The closed set of supported iterables is:

| Iterable | Iteration binding type | Traversal order |
| --- | --- | --- |
| `List[T]` | `T` | Position order |
| `Set[T]` | `T` | Insertion order |
| `Map[K, V]` | `MapEntry[K, V]` | Key insertion order |

`MapEntry[K, V]` is a record with fields `key: K` and `value: V`. It uses the map's key/value eligibility requirements. Its type and named constructor `MapEntry[K, V](key: key, value: value)` are imported from `@std/collections.ms`; field access is ordinary record access. Iteration infers the entry type without requiring an import of its name. It is not a positional pair. Destructure an entry inside the body when convenient.

```manuscript
fn total(values: Map[String, Int]) -> Int:
    var sum = 0
    for entry in values:
        let {key, value} = entry
        sum += value
    return sum
```

`for [key, value] in values:` is rejected at parsing. Iterating a number, text, optional, function, or arbitrary object with a `next` method is rejected at type checking. Each iteration creates a new binding and lexical scope. Assigning to the iteration binding is rejected; an outer mutable accumulator can be reassigned.

## Repeating while a condition holds

```manuscript
fn count_down(start: Int) -> Int:
    var remaining = start
    while remaining > 0:
        remaining = remaining - 1

    return remaining
```

The condition is tested as a `Bool`. Each iteration updates `remaining`; the loop ends when the comparison is false.

A `while` reevaluates its condition before every iteration, including after `continue`. A `for` continues by selecting its next element and terminates after the last element. An empty iterable executes no body. A false initial `while` condition also executes no body.

## Exiting an iteration

`break` and `continue` select the nearest enclosing loop within the same function body. They have no labels or arguments and are rejected outside a loop. An anonymous function inside a loop cannot break or continue that enclosing loop. `return` exits the current function, including when it appears in a loop body. Unreachable loop-control statements still need a valid enclosing loop.

`break`, `continue`, and `return` leave different control-flow paths, but each runs cleanup for the scopes it exits. Each loop iteration has its own scope. Resources registered with `with` in an iteration close when that iteration exits. A plain `let` declaration does not register cleanup. See [lexical cleanup](../cleanup/_index.md) for the cleanup order and fault rules.

## Cancellation

Each loop back-edge is a cancellation checkpoint, so CPU-bound loops respond promptly to cancellation without explicit calls. See propagation and checkpoints for all runtime checkpoints.
