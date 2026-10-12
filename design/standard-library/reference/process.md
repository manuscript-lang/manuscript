+++
title = "process"
+++

# @std/process.ms

Import each required symbol with `import Name from "@std/process.ms"`.

## CommandError {data-api-kind="Alternative"}

```manuscript
CommandError: CommandError
case InvalidInput
case Unavailable
case TimedOut
case OutputLimit
case Failed(message: String)
```

## CommandOutput {data-api-kind="Record"}

```manuscript
CommandOutput: CommandOutput
field exit_code: Int
field stdout: Bytes
field stderr: Bytes
```

## Commands {data-api-kind="Interface"}

```manuscript
Commands: Commands
operation run: fn(program: String, arguments: List[String], input: Bytes, max_output_bytes: Int, timeout: Duration)->Result[CommandOutput, CommandError]
```

