+++
title = "Streams and pipes"
weight = 2
+++

# Streams and pipes

A stream is anything that produces or accepts values over time and can wait. `ReadStream[T]` produces values and `WriteStream[T]` accepts them. Files, sockets, standard input and output, processes, pipes and decoded formats are all one of these with a concrete `T`. Files, sockets and stdio carry `Bytes`; `stdout()` and `stderr()` accept `String`.

Both types are opaque, own what is behind them, and are `Closeable`: scope end closes them, and `close` never waits.

## Reading

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

- `read()` returns a `Promise[T?]` for one step; `none` marks the end.
- `wait()` returns the items for `for item in s.wait()`. Each item is `T!`, so a failure arrives in the loop and ends it.
- The loop holds the stream's source until it ends, breaks or fails, then hands it back: after a `break`, `s.read()` or another loop continues from the next item. Inside the loop body, `s.read()` fails with `"EBADF"` ("a read is already waiting"), and `s.close()` closes the source when the loop ends.
- A stream is not an `Iterator`, so a `for` over a stream without `.wait()` is a checker error that points at `.wait()`. `Iterator` is for sequences that never wait, such as `List` and `Map`.

## Writing

- `write(value)` moves the value into the stream's buffer and returns at once. It never waits, so `stdout().write("text")` needs no `wait`. It returns `"EBADF"` once the reader is gone.
- `flush()` returns a promise that finishes when the buffer has drained. This is the backpressure point: write freely, and flush when `buffered()` says enough has piled up.
- `buffered()` reports the items or bytes not yet drained.
- Buffers left at exit are drained by the runtime before the process ends. A drain error after `close` is lost, so call `flush().wait()` first when delivery matters.

```manuscript
fn dump(rows: List[String], out: WriteStream[String]) Unit!:
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
import from_bytes, lines, map, collect from "@std/io/streams.ms"
import expect_equal from "@std/test/test.ms"

fn line_lengths(input: ReadStream[Bytes]) ReadStream[Int]:
    return input | lines | map(fn line: line.length())

test "measure lines":
    let input = from_bytes("first\nok\n".to_bytes())
    let lengths = try collect(line_lengths(input), max_items: 10)
    try expect_equal(lengths, [5, 2])
```

| Step | Result |
| --- | --- |
| `from_list(items)`, `from_bytes(data)` | A stream over a list, or over bytes in chunks. |
| `lines(input)` | UTF-8 lines, cut only at line breaks. |
| `map(input, f)` | Transform each item. |
| `collect(input, max_items)`, `read_all(input, max_bytes)` | Consume a stream into a list or `Bytes`. |
| `copy(input, output)` | Move everything across and return the count. |

Pipelines are pulled lazily by the task that waits on them. Each stage pulls the one before it with a plain call, so only a source that touches the system (a file, socket, pipe or standard input) waits, inside its own `next`; no stage makes a promise per item.

To make your own stream, implement `Source[T]` (`next` may wait) and wrap it with `stream`. To change a stream, implement `Transform[A, B]` and apply it with `through`: `step(value, var out)` writes the output items one input completes, possibly none, to `out`, and `finish(var out)` writes what was held back at the end. Neither waits. A step that fails drops what it wrote, and the failure is the stream's next item; chained transforms run as one fused stage per item.

## Pipes

A `Pipe[T]` is an in-memory stream between promises: any number of writers, one reader, values whole and in order.

```manuscript
var p = pipe[Int](capacity: 64)
var out = p.writer()
let producer = promise(fn: send_numbers(var out))
var total = 0
for n in p.reader().wait():
    total += try n
try producer.wait()
```

- `writer()` returns a new writing end each time, like `dup` on a file descriptor. `reader()` returns the one reading end.
- `capacity` is the level above which a writer's `flush` waits.
- The reader ends when every writer is closed, after it has read what was sent. Closing the reader makes writers fail with `"EBADF"`.
- `write` is a `var fn`, so two promises cannot share one writer; each takes its own. Make one `var` writer per producer before starting the promises: the promise takes it over and may pass it on or write to it, so any number of producers can feed one reader.

`json_reader[T]` and `json_writer[T]` give a typed view of a byte stream, for example to send newline-delimited JSON over a socket.
