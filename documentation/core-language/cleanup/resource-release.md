+++
title = "Closing a resource"
weight = 2
+++

# Closing a resource

Read after explicit close to review when a file becomes unusable; syntax and APIs evolve during alpha.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","files":{"notes.txt":"hello\n"},"stdout":"RUN example.ms::close a file before its scope ends\nPASS example.ms::close a file before its scope ends\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import open from "@std/os/fs.ms"
import expect_equal, expect_error from "@std/test/test.ms"

test "close a file before its scope ends":
    var file = try open("notes.txt", flags: "r", mode: 0)
    try file.close()
    let cause = try expect_error(file.read_lines(max_lines: 1))
    try expect_equal(cause.kind, "EBADF")
```

```sh
printf 'hello\n' > notes.txt
ms test example.ms
```

```text
RUN example.ms::close a file before its scope ends
PASS example.ms::close a file before its scope ends
1 tests, 0 failed
```

- Flush before close when delivery matters: descriptors drain bytes; pipes wait for queue ≤ capacity.
- Built-in ends close without awaiting delivery; custom cleanup may wait. Scope-end close remains idempotent.

Next: [streams](../concurrency/streams.md), [FileHandle](../../standard-library/reference/os/fs.ms.md#filehandle) and [close failures](closeable.md#a-close-returns-a-result).
