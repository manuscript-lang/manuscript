+++
title = "Copy and watch files"
+++

# Copy and watch files

Review filesystem errors, repeatable copying, and watch-event handling. APIs may evolve during alpha.

## Handle an invalid glob limit

<!-- manuscript-example: {"mode":"test","filename":"glob-limit.ms","stdout":"RUN glob-limit.ms::glob-limit\nPASS glob-limit.ms::glob-limit\n1 tests, 0 failed\n"} -->
```manuscript {filename="glob-limit.ms"}
import glob, GlobOptions from "@std/os/fs.ms"
import expect_equal from "@std/test/test.ms"

test "glob-limit":
    let result = glob(".", GlobOptions(patterns: ["*.ms"], max_entries: -1))
    match result:
        ok(_): return error(Error("expected an invalid limit"))
        error(cause): try expect_equal(cause.kind, "EINVAL")
```

```sh
ms test glob-limit.ms
```

```text
RUN glob-limit.ms::glob-limit
PASS glob-limit.ms::glob-limit
1 tests, 0 failed
```

## Copy a file repeatedly

<!-- manuscript-example: {"mode":"test","filename":"copy-file.ms","stdout":"RUN copy-file.ms::copy-file\nPASS copy-file.ms::copy-file\n1 tests, 0 failed\n"} -->
```manuscript {filename="copy-file.ms"}
import CopyOptions, copy, read_file, write_file from "@std/os/fs.ms"
import expect_equal from "@std/test/test.ms"

test "copy-file":
    try write_file("a.txt", "hello", replace: true).wait()
    try copy("a.txt", "b.txt", CopyOptions(replace: true))
    let contents = try read_file("b.txt").wait()
    try expect_equal(contents.decode_utf8(), "hello")
```

```sh
ms test copy-file.ms
```

```text
RUN copy-file.ms::copy-file
PASS copy-file.ms::copy-file
1 tests, 0 failed
```

## Observe a filesystem change

<!-- manuscript-example: {"mode":"test","filename":"watch-files.ms","stdout":"RUN watch-files.ms::watch-files\nPASS watch-files.ms::watch-files\n1 tests, 0 failed\n"} -->
```manuscript {filename="watch-files.ms"}
import watch, WatchOptions from "@std/os/fs.ms"
import seconds from "@std/os/time.ms"
import expect_equal from "@std/test/test.ms"

test "watch-files":
    var watcher = try watch(".", options: WatchOptions(interval: seconds(1)))
    try watcher.close()
```

```sh
ms test watch-files.ms
```

```text
RUN watch-files.ms::watch-files
PASS watch-files.ms::watch-files
1 tests, 0 failed
```

See the [API reference](../reference/os/fs.ms.md) for signatures and contracts, or continue with [standard-library examples](_index.md).
