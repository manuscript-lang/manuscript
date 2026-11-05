+++
title = "Concurrent tasks"
weight = 8
+++

# Concurrent tasks

Start independent calculations and collect their results in input order. Manuscript is in alpha; syntax and APIs evolve.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","stdout":"RUN example.ms::collect work in input order\nPASS example.ms::collect work in input order\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import promise, wait_all from "@std/concurrency/promise.ms"
import expect_equal from "@std/test/test.ms"

test "collect work in input order":
    let first = promise(fn: ok(3 * 3))
    let second = promise(fn: ok(4 * 4))
    let squares = try wait_all([first, second])
    try expect_equal(squares, [9, 16])
```

```sh
ms test example.ms
```

```text
RUN example.ms::collect work in input order
PASS example.ms::collect work in input order
1 tests, 0 failed
```

<a id="starting-waiting-and-sharing"></a>

- `promise` starts eagerly; `wait_all` preserves input order. Some stream reads defer work until wait.
- Shared captures are read-only. Send updates through a pipe to one owner.

Next: [promises](promises.md), [streams](streams.md) and [HTTP serving](http-server.md).
