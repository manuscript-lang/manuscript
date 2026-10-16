+++
title = "Manuscript — a language for the agentic era"
weight = 1
bookToC = false
description = "Readable code. Native executables. One complete toolchain."
+++

{{< docs-home >}}
<!-- manuscript-example: {"mode":"run","args":["Ada"],"stdout":"Hello, Ada!\n","cases":[{"stdout":"Hello, world!\n"}]} -->
```manuscript {filename="hello.ms"}
import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

export fn main() -> Int:
    let name = arguments().at(0).unwrap_or("world")
    let message = "Hello, {name}!\n".to_bytes()
    match stdout().write(message):
        ok(_): return 0
        error(_): return 1
```
{{< /docs-home >}}
