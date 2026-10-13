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
        total = total + value

    return total
```

The list contains integers. Each iteration binds an element and updates the accumulator. Addition uses checked `Int` arithmetic, so overflow is a [programming fault](../errors/faults.md).

## Counting loops

Use a counter and `while` to repeat work a fixed number of times without allocating a list. This complete test visits indexes 0 through 4:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/faults.ms"

test "five iterations":
    var index = 0
    var total = 0
    while index < 5:
        total = total + index
        index = index + 1
    if index != 5 or total != 10:
        return panic("Expected five iterations and total 10")
```

Increment the counter before any `continue` that would skip its update. With a nonpositive iteration count, an initial `index = 0` and condition `index < count` execute no body.

When you need a list of numbers, import `range` from `@std/collections.ms`. It includes `start`, excludes `end`, and requires an explicit nonzero `step`. It returns `Result[List[Int], CollectionError]`, so handle the result before using `for`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import range from "@std/collections.ms"
import panic from "@std/faults.ms"

test "sum indexes":
    match range(start: 0, end: 5, step: 1):
        ok(indexes):
            var total = 0
            for index in indexes:
                total = total + index
            if total != 10:
                return panic("Expected 10, got {total}")
        error(cause):
            return panic("Could not build range: {cause.message()}")

test "zero step is rejected":
    let cause = match range(start: 0, end: 5, step: 0):
        ok(_): return panic("Expected an invalid step error")
        error(cause): cause

    match cause:
        InvalidInput: unit
        _: return panic("Expected InvalidInput")

```

Save either complete example as `test.ms` and run `ms test test.ms`. A failed check calls `panic`; see [testing](../../learn/testing.md).

A positive step moves upward; a negative step moves downward. `range(start: 5, end: 0, step: -2)` produces `[5, 3, 1]`. Equal endpoints or a step directed away from the end produce an empty list. `step: 0` returns `InvalidInput`; `max_items` optionally bounds allocation and returns `LimitExceeded` when exceeded. See the [range declaration](../../standard-library/reference/collections.md#range).

`for index in 0..5:` is unsupported. A direct `for index in range(...)` also fails because a `Result` is not an iterable. In a function returning a compatible `Result`, `let indexes = try range(start: 0, end: 5, step: 1)` is another way to unwrap before the loop.

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
        sum = sum + value
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

Each loop back-edge is a cancellation checkpoint, so CPU-bound loops respond promptly to cancellation without explicit calls. See [propagation and checkpoints](../../concurrency/cancellation.md#propagation-and-checkpoints) for all runtime checkpoints.
