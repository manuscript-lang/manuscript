+++
title = "Manuscript — The language for the agentic era."
weight = 1
bookToC = false
description = "A statically typed, natively compiled language designed for agents to write and humans to understand: Python-like syntax, ownership without a garbage collector, concurrency without async, and compiler feedback an agent can act on."
+++

{{< docs-home >}}
<!-- manuscript-example: {"mode":"run","args":["Ada"],"stdout":"Hello, Ada!\n","cases":[{"stdout":"Hello, world!\n"}]} -->
```manuscript {filename="hello.ms"}
from "@std/process.ms" import arguments
from "@std/io.ms" import stdout

export def main() -> Int:
    let name = arguments().get(0, default: "world")
    let message = f"Hello, {name}!\n"
    if stdout().write(message).is_error():
        return 1
    return 0
```
{{< /docs-home >}}
