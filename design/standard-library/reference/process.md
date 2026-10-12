+++
title = "process"
+++

# @std/process.ms

Import each required symbol with `import Name from "@std/process.ms"`.

## CommandError {data-api-kind="Alternative"}

```manuscript
type CommandError:
    case InvalidInput
    case Unavailable
    case TimedOut
    case OutputLimit
    case Failed(message: String)
```

```manuscript
impl Error for CommandError:
    fn message() -> String
```

## CommandOutput {data-api-kind="Record"}

```manuscript
type CommandOutput:
    exit_code: Int
    stdout: Bytes
    stderr: Bytes
```

## Commands {data-api-kind="Interface"}

```manuscript
interface Commands:
    fn run(program: String, arguments: List[String], input: Bytes, max_output_bytes: Int, timeout: Duration) -> Result[CommandOutput, CommandError]
```

