+++
title = "Concurrent tasks"
weight = 8
+++

# Concurrent tasks

A call that can wait starts its work at once and returns a `Promise[T]`. `wait()` gives the result, so there is no `async` or `await`: any function can wait, and callers do not change. `promise(fn: ...)` runs your own function the same way, on a thread the runtime picks.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import promise, wait_all from "@std/concurrency/promise.ms"
import expect_equal from "@std/test/test.ms"

fn square(n: Int) Int:
    return n * n

test "run work at once and collect it":
    let first = promise(fn: ok(square(3)))
    let second = promise(fn: ok(square(4)))
    let results = try wait_all([first, second])
    try expect_equal(results, [9, 16])
```

- A promise only reads what it captures. Concurrent code never changes a shared value; give state one owner and send it values over a `pipe`.
- `wait(timeout: ...)` stops waiting and cancels the promise when the limit passes. Dropping an unfinished promise cancels it and waits for it to end, so work never outlives the values it uses.
- A fault inside a promise ends only that promise; `wait` reports it as a failure.
- `wait_all` returns results in order and cancels the rest on the first error; `wait_first` returns the first result.
- Cancellation is delivered at the next wait, and a loop that never waits is not stopped. Lint rule **MSL111** flags a `while true` loop that neither waits nor exits.

The API reference is generated from `stdlib/concurrency/promise.ms`.
