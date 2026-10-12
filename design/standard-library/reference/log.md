+++
title = "log"
+++

# @std/log.ms

Import each required symbol with `import Name from "@std/log.ms"`.

## LogError

Kind: alternative.

```text
LogError: LogError
implements: Error
case InvalidInput
case InvalidData
case LimitExceeded
case Io(cause: IoError)
operation message: fn()->String
```

## write

Kind: fn.

```text
write: fn(output: WriteStream & Shareable, level: String, message: String, fields: Map[String, String], max_bytes: Int)->Result[Unit, LogError]
```

