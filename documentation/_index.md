+++
title = "Manuscript — The language for the agentic era."
weight = 1
bookToC = false
description = "Agents write. Humans understand."
+++

{{< docs-home >}}
<!-- manuscript-example: {"mode":"run","args":["Ada"],"stdout":"Hello, Ada!\n","cases":[{"stdout":"Hello, world!\n"}]} -->
```manuscript {filename="hello.ms"}
import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let name = arguments().at(0).get("world")
    let message = "Hello, {name}!\n".to_bytes()
    if stdout().write(message).is_error():
        return 1
    return 0
```
{{< /docs-home >}}
