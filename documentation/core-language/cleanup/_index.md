+++
title = "Managing resources"
weight = 7
+++

# Managing resources

Read `notes.txt` and let its owner close the file at scope end. Manuscript is in alpha; syntax and APIs evolve.

<!-- manuscript-example: {"mode":"test","filename":"example.ms","files":{"notes.txt":"hello\n"},"stdout":"RUN example.ms::read a note within its scope\nPASS example.ms::read a note within its scope\n1 tests, 0 failed\n"} -->
```manuscript {filename="example.ms"}
import open from "@std/os/fs.ms"
import expect_equal from "@std/test/test.ms"

test "read a note within its scope":
    let file = try open("notes.txt", flags: "r", mode: 0)
    let lines = try file.read_lines(max_lines: 1)
    try expect_equal(lines, ["hello"])
```

```sh
printf 'hello\n' > notes.txt
ms test example.ms
```

```text
RUN example.ms::read a note within its scope
PASS example.ms::read a note within its scope
1 tests, 0 failed
```

- The successful binding owns the file. Scope-end cleanup closes it without special resource syntax.

Next: [scope-end cleanup](scopes.md), [explicit close](resource-release.md), [Closeable](closeable.md), [order](exit-order.md) and [failures](cleanup-faults.md).
