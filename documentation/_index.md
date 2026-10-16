+++
title = "Manuscript — a language for the agentic era"
weight = 1
bookToC = false
description = "Turn your next idea into a native program. Manuscript brings readable code, explicit types, and tools for coding agents and the people working with them into one download."
+++

{{< docs-home >}}
<!-- manuscript-example: {"mode":"run","args":["Ada"],"stdout":"Hello, Ada!\n","cases":[{"stdout":"Hello, world!\n"}]} -->
```manuscript {filename="hello.ms"}
import arguments from "@std/cli.ms"
import stdout from "@std/io.ms"

export fn main() -> Int:
    let name = arguments().at(0).unwrap_or("world")
    match stdout().write("Hello, {name}!\n".to_bytes()):
        ok(_): return 0
        error(_): return 1
```
{{< /docs-home >}}

## What will you build first?

- **A tool that saves you a daily chore.** Read arguments, transform files, and work with structured data. [Try the task recipes](learn/common-tasks.md)
- **A service that connects things.** Make HTTP requests, handle connections, and run work concurrently. [Explore the standard library](standard-library/_index.md)
- **Your next project with a coding agent.** Give it a small language, searchable APIs, and compiler feedback it can act on. [See the agent workflow](developer-tooling/implementation.md#commands-for-agents)

## Your first program is one download away.

[Get started with Manuscript →](learn/getting-started.md)

Download a release, run an example, and make it your own. Already writing Manuscript? [Open the docs](learn/_index.md) or jump to the [API reference](standard-library/reference/_index.md).
