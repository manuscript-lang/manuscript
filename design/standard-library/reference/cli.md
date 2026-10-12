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
field stdin: ReadStream & Shareable
field stdout: WriteStream & Shareable
field stderr: WriteStream & Shareable
field files: Files & Shareable
field clock: Clock & Shareable
field network: Network & Shareable
field commands: Commands & Shareable
field filesystem: FileSystem & Shareable
field entropy: Entropy & Shareable
field wall_clock: WallClock & Shareable
field system: System & Shareable
```

