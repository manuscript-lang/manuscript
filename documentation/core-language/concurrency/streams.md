+++
title = "Streams and pipes"
weight = 2
+++

# Streams and pipes

Trace producer shutdown to review whether a pipe’s reader can finish; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::sum a producer stream\nPASS example.ms::sum a producer stream\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import pipe, WriteStream from "@std/io/io.ms"
import promise from "@std/concurrency/promise.ms"
import expect_equal from "@std/test/test.ms"

fn send(var output: WriteStream[Int]) Unit!:
    for number in [1, 2, 3]:
        try output.write(number)
    try output.close()
    return ok(unit)

test "sum a producer stream":
    var values = pipe[Int](capacity: 64)
    var output = values.writer()
    let producer = promise(fn: send(var output))
    var total = 0
    for item in values.reader().wait():
        total += try item
    try producer.wait()
    try expect_equal(total, 6)
```

```sh
ms test example.ms
```

```text
RUN example.ms::sum a producer stream
PASS example.ms::sum a producer stream
1 tests, 0 failed
```

<a id="reading"></a>
<a id="writing"></a>
<a id="pipelines"></a>
<a id="pipes"></a>

- Reads are lazy; stream items carry `T!` failures. Custom sources and sinks may wait.
- Pipe flush applies backpressure and may leave queued items; close alone does not guarantee delivery.

Next: [promises](promises.md), [stream helpers](../../standard-library/reference/io/streams.ms.md), [stream and pipe contracts](../../standard-library/reference/io/io.ms.md) and [delivery before close](../cleanup/resource-release.md).
