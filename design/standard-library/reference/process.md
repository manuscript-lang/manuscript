+++
title = "process"
+++

# @std/process.ms

Import each required symbol with `import Name from "@std/process.ms"`.

## CommandError

Kind: alternative.

```text
CommandError: CommandError
implements: Error
case InvalidInput
case Unavailable
case TimedOut
case OutputLimit
case Failed(message: String)
operation message: fn()->String
```

## CommandOutput

Kind: record.

```text
CommandOutput: CommandOutput
field exit_code: Int
field stdout: Bytes
field stderr: Bytes
```

## Commands

Kind: interface.

```text
Commands: Commands
operation run: fn(program: String, arguments: List[String], input: Bytes, max_output_bytes: Int, timeout: Duration)->Result[CommandOutput, CommandError]
```

