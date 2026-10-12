+++
title = "Loops"
weight = 25
+++

# Loops

[Core language guide](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

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

The list contains shareable integers. Each iteration binds an element and updates the accumulator. Addition uses checked `Int` arithmetic, so overflow is a [programming fault](../errors/faults.md).

## Iterable types and binding

Evaluate a `for`'s iterable expression once before entering the loop. The loop introduces one immutable identifier per iteration; it does not accept a binding pattern or a type annotation. The closed set of supported iterables is:

| Iterable | Iteration binding type | Traversal order |
| --- | --- | --- |
| `List[T]` | `T` | Position order |
| `Set[T]` | `T` | Insertion order |
| `Map[K, V]` | `MapEntry[K, V]` | Key insertion order |

`MapEntry[K, V]` is an immutable record with fields `key: K` and `value: V`. It uses the map's key/value eligibility requirements. Its type and named constructor `MapEntry[K, V](key: key, value: value)` are imported from `@std/collections.ms`; field access is ordinary record access. Iteration infers the entry type without requiring an import of its name. It is not a positional pair. Destructure an entry inside the body when convenient.

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

`break`, `continue`, and `return` leave different control-flow paths, but each runs cleanup for the scopes it exits. Each loop iteration has its own scope. Resources registered with `with` in an iteration close when that iteration exits. A plain `let` declaration does not register cleanup. See [lexical cleanup](../../ownership-and-cleanup/cleanup/_index.md) for the cleanup order and fault rules.

## Cancellation

Each loop back-edge is a cancellation checkpoint, so CPU-bound loops respond promptly to cancellation without explicit calls. See [propagation and checkpoints](../../concurrency/cancellation.md#propagation-and-checkpoints) for all runtime checkpoints.

[Previous: Conditionals](conditionals.md) · [Next: Pattern matching](pattern-matching.md)
