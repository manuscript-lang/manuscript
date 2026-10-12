+++
title = "cli"
+++

# @std/cli.ms

Import each required symbol with `import Name from "@std/cli.ms"`.

## Process {data-api-kind="Record"}

```manuscript
Process: Process
field arguments: List[String]
field environment: Map[String, String]
field stdin: ReadStream
field stdout: WriteStream
field stderr: WriteStream
field files: Files
field clock: Clock
field network: Network
field commands: Commands
field filesystem: FileSystem
field entropy: Entropy
field wall_clock: WallClock
field system: System
```

