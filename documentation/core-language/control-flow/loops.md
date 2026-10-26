+++
title = "Loops"
weight = 2
+++

# Loops

`for` / `in` visits collection values; `while` repeats while a `Bool` condition holds. `break` ends the loop; `continue` starts the next iteration. Loops are statements: no labels, result values, or custom iteration protocol.

## Traversing a list

```manuscript
def sum(values: List[Int]) -> Int:
    var total = 0
    for value in values:
        total += value

    return total
```

## Counting loops

`start..end` includes `start`, excludes `end`, and counts up by one; it needs no import. It is the call `range(start, end)` from `@std/collections.ms`, so it binds looser than `+` and `-` (`0..n + 1` is `0..(n + 1)`), is not chainable, and takes `Int` bounds. A `for` over `start..end` or a direct `range` call is a counter loop that allocates no list.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/core.ms" import panic

test "sum indexes":
    var total = 0
    for index in 0..5:
        total += index
    if total != 10:
        return panic(f"Expected 10, got {total}")
```

`end <= start` visits nothing. Bounds are evaluated once, in order, before the first iteration. As a plain value, `range(0, count)` is a `List[Int]`; over 268,435,456 items faults, so use `range_by(max_items:)` for larger lists.

Use `while` with a counter for other steps or computed exits:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
from "@std/core.ms" import panic

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
from "@std/collections.ms" import range_by
from "@std/testing.ms" import expect_equal

test "sum even indexes":
    let indexes = try range_by(start: 0, end: 6, step: 2)
    var total = 0
    for index in indexes:
        total += index
    try expect_equal(total, 6)
```

`try` unwraps the range in a function or test whose error type is compatible; `get([])` supplies a fallback. Use `range_by` for steps; `..` has no step form. See the [range declarations](../../standard-library/reference/collections.md#range).

## Iterable types and binding

The iterable is evaluated once. Traversal borrows the collection for the loop body; mutating, reassigning, or moving that collection while the borrow is live is rejected. The loop variable is one immutable name per iteration, with no pattern or annotation. Supported iterables:

| Iterable | Iteration binding type | Traversal order |
| --- | --- | --- |
| `List[T]` | `T` | Position order |
| `Set[T]` | `T` | Insertion order |
| `Map[K, V]` | `MapEntry[K, V]` | Key insertion order |
| `Iterator[T]` implementation | `T` | Order of `next()` results |

`MapEntry[K, V]` is a record with `key: K` and `value: V` (constructor from `@std/collections.ms`; iteration needs no import). It is not a positional pair; destructure it in the body. The entry is borrowed from the map, not copied. A loop header `for e in m.entries()`, `m.values()` or `m.keys()` over a map the body does not change walks the map the same way instead of building the list; when the body changes the map, the list is built first, so the loop sees the entries as they were.

```manuscript
def total(values: Map[String, Int]) -> Int:
    var sum = 0
    for entry in values:
        let {key: _key, value} = entry
        sum += value
    return sum
```

`for [key, value] in values:` is a parse error. Numbers, text, optionals, functions, and types that merely have a `next` method without `impl Iterator` are not iterable. Each iteration has a new scope; assigning to the loop variable is rejected, but an outer `var` can change.

## Iterators

A type that implements `Iterator[T]` from `@std/core.ms` is iterable: `for item in source:` calls `source.next()` until it returns `none`, binding each `T`. It is the same as `while True:` with `if let item = source.next(): ... else: break`, so `break`, `continue`, and `return` behave as in any loop and the body may use the loop variable as `T`. A variable or field path is advanced in place and must be declared `var`; any other expression (a call, say) is held by the loop alone. After the loop, an in-place iterator keeps its final state, which is how `LineReader.error()` reports why reading stopped.

<!-- manuscript-example: {"mode":"run","stdout":"3\n2\n1\n"} -->
```manuscript
from "@std/core.ms" import Iterator
from "@std/io.ms" import stdout

type Countdown:
    left: Int

impl Iterator[Int] for Countdown:
    var def next() -> Optional[Int]:
        if self.left == 0:
            return none
        self.left -= 1
        return some(self.left + 1)

export def main() -> Int:
    for n in Countdown(3):
        if stdout().write(f"{n}\n").is_error():
            return 1
    return 0
```

## Repeating while a condition holds

```manuscript
def count_down(start: Int) -> Int:
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

Tasks share one thread and are cancelled at their next wait, so a loop that never waits is not stopped by cancellation or a timeout and keeps other tasks from running. Wait inside the loop, or poll `cancelled()` and return. Lint rule **MSL111** flags a `while True` loop in a module that imports `@std/tasks.ms` when its body neither waits nor exits.
