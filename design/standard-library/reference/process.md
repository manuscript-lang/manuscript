+++
title = "process"
+++

# @std/process.ms

Import each required symbol with `import Name from "@std/process.ms"`.

## CommandError

Kind: alternative.

```manuscript
CommandError: CommandError
case InvalidInput
case Unavailable
case TimedOut
case OutputLimit
case Failed(message: String)
```

## CommandOutput

Kind: record.

```manuscript
CommandOutput: CommandOutput
field exit_code: Int
field stdout: Bytes
field stderr: Bytes
```

## Commands

Kind: interface.

```manuscript
Commands: Commands
operation run: fn(program: String, arguments: List[String], input: Bytes, max_output_bytes: Int, timeout: Duration)->Result[CommandOutput, CommandError]
```

