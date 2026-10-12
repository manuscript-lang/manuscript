+++
title = "cli"
+++

# @std/cli.ms

Import each required symbol with `import Name from "@std/cli.ms"`.

## Process {data-api-kind="Record"}

```manuscript
type Process:
    arguments: List[String]
    environment: Map[String, String]
    stdin: ReadStream
    stdout: WriteStream
    stderr: WriteStream
    files: Files
    clock: Clock
    network: Network
    commands: Commands
    filesystem: FileSystem
    entropy: Entropy
    wall_clock: WallClock
    system: System
```

