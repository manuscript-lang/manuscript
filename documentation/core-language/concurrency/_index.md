+++
title = "Concurrent tasks"
weight = 8
+++

# Concurrent tasks

`promise(fn: ...)` starts concurrent work on a thread the runtime picks and returns a `Promise[T]`; `wait()` takes its result. Any function can wait, including functions that return a value directly, so there is no `async` or `await`. Streams are pulled lazily: a promise returned by `ReadStream.read()` defers its read until it is waited on. Values that arrive over time travel on [streams](streams.md), and an in-memory `pipe` connects promises.

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

## The rules

1. A `Promise[T]` represents an operation with one result. `wait()` gives `T!` and takes the result once. `promise(fn: ...)` starts work eagerly; stream reads may defer work until the wait.
2. A task pauses at a wait, including waits inside called functions. Code between two waits runs without interleaving.
3. `promise(fn: ...)` runs on a thread the runtime picks and stays there. A CPU-heavy promise delays the promises sharing its thread until it waits. A promise may borrow what it captures, so the values it reads must outlive it (rule 4).
4. Work you start ends before the values it uses. Dropping a promise cancels it and waits for it to end.
5. Concurrent code can read shared values but never change them. To change shared state, give it one owner and send it values over a `pipe`.
6. Errors and faults inside a promise come back from `wait` as errors. A fault outside any promise ends the program.

All threads share one heap and values move between them by pointer, so nothing is copied or encoded when a value crosses a thread. There are no channels, task groups, locks or shared cells.

The terminal (raw mode and key events in `@std/io/io.ms`) belongs to the main thread: a promise on another thread that uses it faults with "only available on the main thread", so do terminal work in the main task and send it values.

| Page | What you will learn |
| --- | --- |
| [Promises](promises.md) | Start work with a deadline, wait, cancel, and collect many results. |
| [Streams and pipes](streams.md) | Read and write values over time, build pipelines, and pass values between promises. |
| [HTTP server](http-server.md) | Serve on every core with one `serve` call. |

The API reference is generated from `stdlib/concurrency/promise.ms`, `stdlib/io/io.ms` and `stdlib/net/net.ms`.
