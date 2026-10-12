+++
title = "log"
+++

# @std/log.ms

Import each required symbol with `import Name from "@std/log.ms"`.

## LogError {data-api-kind="Alternative"}

```manuscript
type LogError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Io(cause: IoError)
```

```manuscript
impl Error for LogError:
    fn message() -> String
```

## write {data-api-kind="Function"}

```manuscript
fn write(output: WriteStream, level: String, message: String, fields: Map[String, String], max_bytes: Optional[Int] = none) -> Result[Unit, LogError]
```

