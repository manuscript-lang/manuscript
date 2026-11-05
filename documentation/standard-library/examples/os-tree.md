+++
title = "Work with an in-memory filesystem"
+++

# Work with an in-memory filesystem

Follow a file write and read without touching the host filesystem. APIs may evolve during alpha.

## Read an in-memory file

<!-- manuscript-example: {"mode":"test","filename":"memory-files.ms","stdout":"RUN memory-files.ms::memory-files\nPASS memory-files.ms::memory-files\n1 tests, 0 failed\n"} -->
```manuscript {filename="memory-files.ms"}
import memory_tree, walk from "@std/os/tree.ms"
import expect_equal from "@std/test/test.ms"

test "memory-files":
    var tree = memory_tree()
    try tree.write_file("hello.txt", "hello".to_bytes())
    let entries = try walk(tree)
    try expect_equal(entries.length(), 1)
    try expect_equal(entries[0].path, "hello.txt")
```

```sh
ms test memory-files.ms
```

```text
RUN memory-files.ms::memory-files
PASS memory-files.ms::memory-files
1 tests, 0 failed
```

See the [API reference](../reference/os/tree.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
