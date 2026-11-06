+++
title = "Streams and pipes"
weight = 2
+++

# Streams and pipes

A stream is anything that produces or accepts values over time and can wait. `ReadStream[T]` produces values and `WriteStream[T]` accepts them. Files, sockets, standard input and output, processes, pipes and decoded formats are all one of these with a concrete `T`. Files, sockets and stdio carry `Bytes`; `stdout()` and `stderr()` accept `String`.

Both types are opaque, own what is behind them, and are `Closeable`: scope end closes them. Built-in descriptor and pipe ends close without waiting for delivery; a custom source or sink controls its own close behavior and may wait.

## Reading

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import ReadStream from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import lines from "@std/io/streams.ms"

fn count_errors(input: ReadStream[Bytes]) Int!:
    var errors = 0
    for line in (input | lines).wait():       // each step waits
        if (try line).contains("ERROR"):
            errors += 1
    return ok(errors)
```

- `read()` returns a `Promise[T?]` for one step and defers the read until a wait; `none` marks the end. See [Promises](promises.md) for waiting, timeouts and cancellation.
- `wait()` returns the items for `for item in s.wait()`. Each item is `T!`, so a failure arrives in the loop and ends it.
- The loop holds the stream's source until it ends, breaks or fails, then hands it back: after a `break`, `s.read()` or another loop continues from the next item. Inside the loop body, `s.read()` fails with `"EBADF"` ("a read is already waiting"), and `s.close()` closes the source when the loop ends.
- A stream is not an `Iterator`, so a `for` over a stream without `.wait()` is a checker error that points at `.wait()`. `Iterator` is for sequences that never wait, such as `List` and `Map`.

## Writing

- `write(value)` passes the value to the sink and returns a `Result` directly. Built-in descriptor and pipe writers buffer without waiting, so `stdout().write("text")` needs no `wait`. A custom sink may wait in its `put` implementation. A pipe write returns `"EBADF"` once the reader is gone.
- `flush()` returns a promise for the destination’s backpressure or drain condition. File and socket streams wait for queued bytes to drain; a pipe waits until at most `capacity` values remain queued. Flush when `buffered()` says enough has piled up.
- `buffered()` reports the items or bytes not yet drained.
- The runtime drains buffered descriptor writes before the process ends. To handle a drain failure, call `flush().wait()` before closing. A pipe flush is not an acknowledgement that the reader has consumed every value; close the writers and let the reader reach the end when you need that guarantee.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import WriteStream from "@std/io/io.ms"

fn dump(rows: List[String], var out: WriteStream[String]) Unit!:
    for row in rows:
        try out.write("{row}\n")
        if out.buffered() > 65536:
            try out.flush().wait()
    try out.flush().wait()
    return ok(unit)
```

## Pipelines

Each step in `@std/io/streams.ms` takes its input first and by move, so a pipeline is the `|` operator and a reusable pipeline is an ordinary function:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import Bytes from "@std/bytes.ms"
import ReadStream from "@std/io/io.ms"
import from_bytes, lines, filter, map, collect from "@std/io/streams.ms"
import expect_equal from "@std/test/test.ms"

fn line_lengths(input: ReadStream[Bytes]) ReadStream[Int]:
    return input | lines | filter(fn line: line != "") | map(fn line: line.length())

test "measure lines":
    let input = from_bytes("first\n\nok\n".to_bytes())
    let lengths = try collect(line_lengths(input), max_items: 10)
    try expect_equal(lengths, [5, 2])
```

| Step | Result |
| --- | --- |
| `from_list(items)`, `from_bytes(data)` | A stream over a list, or over bytes in chunks. |
| `lines(input)` | UTF-8 lines, cut only at line breaks. |
| `map(input, f)` | Transform each item. |
| `filter(input, keep)` | The items for which `keep` is true; items are cloned, so `T` is `Clonable`. |
| `take(input, count)` | At most the first `count` items, never reading past them, so it ends an endless stream. |
| `collect(input, max_items)`, `read_all(input, max_bytes)` | Consume a stream into a list or `Bytes`. |
| `fold(input, start, f)` | Combine all items into one value with `f(total, item)`. |
| `copy(input, output)` | Move everything across and return the count. |

Consumers such as `collect` wait internally and return a value directly. Pipelines are pulled lazily by the task that waits on them. Built-in stages pull the preceding stage with plain calls. A source may wait for input, and a custom source or transform may also wait inside its implementation; composing stages does not require starting separate work for each item.

To make your own stream, implement `Source[T]` (`next` may wait) and wrap it with `stream`. To change a stream, implement `Transform[A, B]` and apply it with `through`: `step(value, var out)` writes the output items one input completes, possibly none, to `out`, and `finish(var out)` writes what was held back at the end. Built-in transforms process each item directly; a custom `step` or `finish` may wait. A step that fails drops what it wrote, and the failure is the stream's next item; chained transforms run as one fused stage per item.

## Pipes

A `Pipe[T]` is an in-memory stream between promises: any number of writers, one reader, values whole and in order.

Save as `pipe_test.ms` and run `ms test pipe_test.ms`:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import pipe, WriteStream from "@std/io/io.ms"
import promise from "@std/concurrency/promise.ms"
import expect_equal from "@std/test/test.ms"

fn send_numbers(var out: WriteStream[Int]) Unit!:
    for n in [1, 2, 3]:
        try out.write(n)
    return out.close()

test "sum values from a producer":
    var p = pipe[Int](capacity: 64)
    var out = p.writer()
    let producer = promise(fn: send_numbers(var out))
    var total = 0
    for n in p.reader().wait():
        total += try n
    try producer.wait()
    try expect_equal(total, 6)
```

```text
RUN pipe_test.ms::sum values from a producer
PASS pipe_test.ms::sum values from a producer
1 tests, 0 failed
```

The producer closes its writer after sending the values, allowing the reader's loop to finish. Waiting for the producer also checks its result.

- `writer()` returns a new writing end each time, like `dup` on a file descriptor. `reader()` returns the one reading end.
- `capacity` is the level above which a writer's `flush` waits.
- The reader ends when every writer is closed, after it has read what was sent. Closing the reader makes writers fail with `"EBADF"`.
- `write` is a `var fn`, so two promises cannot share one writer; each takes its own. Make one `var` writer per producer before starting the promises: the promise takes it over and may pass it on or write to it, so any number of producers can feed one reader.

`json_reader[T]` and `json_writer[T]` give a typed view of a byte stream, for example to send newline-delimited JSON over a socket.
