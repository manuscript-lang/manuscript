+++
title = "Streams and pipes"
weight = 2
+++

# Streams and pipes

A stream is anything that produces or accepts values over time and can wait. `ReadStream[T]` produces values and `WriteStream[T]` accepts them. Files, sockets, standard input and output, processes, pipes and decoded formats are all one of these with a concrete `T`. Files, sockets and stdio carry `Bytes`; `stdout()` and `stderr()` accept `String`.

There is one stream type for memory and for waiting sources. A source that touches the system waits inside its own `next`, and only the task that called it sleeps, so no item type says "async" and no promise is made per item. Both types are `Closeable`: scope end closes them, and a stream owns what is behind it. A descriptor write end waits until its queued bytes are delivered before it closes; a custom source or sink controls its own close behavior.

## Reading

`for item in stream` binds `T`. A failed read leaves the loop with its error, as `?` would, so the enclosing function must return a `Result`; a function that does not calls `next()` itself.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import ReadStream from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import lines from "@std/io/streams.ms"

fn count_errors(input: ReadStream[Bytes]) Int!:
    var errors = 0
    for line in input | lines:       // each step may wait for the source
        if line.contains("ERROR"):
            errors += 1
    return ok(errors)
```

- `next()` returns `T?!`: `none` marks the end and an error is a failed read. A closed stream is at its end. `next(timeout: d)` bounds one read: it fails with `ETIMEDOUT` once the read has waited `d` in all (a stalled socket, an empty pipe), so a loop can give up on a silent server. The source may be left mid-item, so close the stream after a timeout.
- A loop over a variable advances it in place and leaves it usable after `break`; a loop over an expression holds the pipeline for the loop and closes it afterwards.
- Cancellation and time limits are not stream API. Run the loop in a promise with `PromiseOptions(timeout: ...)` to limit a whole pipeline; a cancel or timeout lands at the next wait inside `next` and the loop leaves with an error. See [Promises](promises.md).
- A stream is not an `Iterator`. `Iterator` is for sequences that never wait, such as `List` and `Map`.

## Writing

- `write(value)` passes the value to the sink and waits while the sink is full: back pressure. A pipe write waits once more than `capacity` values are queued and returns `"EBADF"` once the reader is gone; a custom sink may wait in its `write`.
- `flush()` returns once everything written has drained. File and socket streams wait for queued bytes to drain; a pipe waits until at most `capacity` values remain queued.
- The runtime drains buffered descriptor writes before the process ends. To handle a drain failure, call `flush()` before closing. A pipe flush is not an acknowledgement that the reader has consumed every value; close the writers and let the reader reach the end when you need that guarantee.

<!-- manuscript-example: {"mode":"check"} -->
```manuscript
import WriteStream from "@std/io/io.ms"

fn dump(rows: List[String], var out: WriteStream[String]) Unit!:
    for row in rows:
        out.write("{row}\n")?
    return out.flush()
```

## Pipelines

Each step in `@std/io/streams.ms` takes its input first and by move, so a pipeline is the `|` operator and a reusable pipeline is an ordinary function. A step pulls its input only inside its own `next`, so a slow consumer slows every step and the source, and nothing reads ahead:

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import Bytes from "@std/bytes.ms"
import ReadStream from "@std/io/io.ms"
import from_bytes, lines, filter, map, collect from "@std/io/streams.ms"
import expect_equal from "@std/test/test.ms"

fn line_lengths(input: ReadStream[Bytes]) ReadStream[Int]:
    return input | lines | filter(fn line: line != "") | map(fn line: line.length())

test "measure lines":
    input := from_bytes("first\n\nok\n".to_bytes())
    lengths := collect(line_lengths(input), max_items: 10)?
    expect_equal(lengths, [5, 2])?
```

| Step | Result |
| --- | --- |
| `from_list(items)`, `from_bytes(data)` | A stream over a list, or over bytes in chunks. |
| `lines(input)` | UTF-8 lines, cut only at line breaks. |
| `map(input, f)` | Transform each item. |
| `filter(input, keep)` | The items for which `keep` is true. |
| `take(input, count)` | At most the first `count` items, never reading past them, so it ends an endless stream. |
| `collect(input, max_items)`, `read_all(input, max_bytes)` | Consume a stream into a list or `Bytes`. |
| `fold(input, start, f)` | Combine all items into one value with `f(total, item)`. |
| `copy(input, output)` | Move everything across, flush, and return the count. |

To make your own stream, implement `Source[T]` (`next` may wait, `close` releases what it holds) and wrap it with `ReadStream(source)`; implement `Sink[T]` (`write`, `flush`, `close`) and wrap it with `WriteStream(sink)`. Closing the stream closes the source or sink once.

To change a stream item by item with a step that may emit zero or more outputs, implement `Transform[A, B]` and apply it with `through`: `step(value, var out)` appends the output items one input completes, possibly none, to the `List[B]` `out`, and `finish(var out)` appends what was held back at the end. A step that fails drops what it appended, and the failure is the stream's next item.

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
        out.write(n)?
    return out.close()

test "sum values from a producer":
    var p = pipe[Int](capacity: 64)
    var out = p.writer()
    producer := promise(fn: send_numbers(var out))
    var total = 0
    for n in p.reader():
        total += n
    producer.wait()?
    expect_equal(total, 6)?
```

```text
RUN pipe_test.ms::sum values from a producer
PASS pipe_test.ms::sum values from a producer
1 tests, 0 failed
```

The producer closes its writer after sending the values, allowing the reader's loop to finish. Waiting for the producer also checks its result.

- `writer()` returns a new writing end each time, like `dup` on a file descriptor. `reader()` returns the one reading end.
- `capacity` is the level above which a writer's `write` and `flush` wait.
- The reader ends when every writer is closed, after it has read what was sent. Closing the reader makes writers fail with `"EBADF"`.
- `write` is a `var fn`, so two promises cannot share one writer; each takes its own. Make one `var` writer per producer before starting the promises: the promise takes it over and may pass it on or write to it, so any number of producers can feed one reader.

`json_reader[T]` and `json_writer[T]` give a typed view of a byte stream, for example to send newline-delimited JSON over a socket.
