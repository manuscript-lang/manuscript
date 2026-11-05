+++
title = "Scope-end cleanup"
weight = 1
+++

# Scope-end cleanup

Keep a file open while reading, then close it automatically. Manuscript is in alpha; syntax and APIs evolve.

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

<a id="what-happens-step-by-step"></a>
<a id="which-values-are-closed"></a>
<a id="control-the-lifetime"></a>

- Standard `Closeable` values close on every exit, including cancellation: inner scopes first, newest bindings first.
- Moves transfer cleanup; records, enums and collections close their owned resources.

Next: [Closeable](closeable.md), [ownership](../types/references.md) and [scope checking](../../contributing/compiler/frontend/scope-checker.md).
