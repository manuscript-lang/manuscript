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
    case Closed
    case Io(cause: IoError)
    case FileSystem(cause: FileSystemError)
```

```manuscript
impl Error for LogError:
    fn message() -> String:
```

## LogLevel {data-api-kind="Alternative"}

```manuscript
type LogLevel:
    case Trace
    case Debug
    case Info
    case Warn
    case Error
    case Fatal
    case Silent
```

## Logger {data-api-kind="Interface"}

```manuscript
interface Logger:
    fn log(level: LogLevel, message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
    fn trace(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
    fn debug(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
    fn info(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
    fn warn(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
    fn error(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
    fn fatal(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
    fn enabled(level: LogLevel) -> Bool
    fn level() -> LogLevel
    fn set_level(level: LogLevel) -> Unit
    fn child(bindings: Map[String, JsonValue]) -> Logger
    fn flush() -> Result[Unit, LogError]
```

## Transport {data-api-kind="Interface"}

```manuscript
interface Transport:
    fn write(data: Bytes) -> Result[Unit, LogError]
    fn flush() -> Result[Unit, LogError]
    fn close() -> Unit
```

## create {data-api-kind="Function"}

```manuscript
fn create(transport: Transport, level: Optional[LogLevel] = none, bindings: Optional[Map[String, JsonValue]] = none, timestamp: Optional[Bool] = none, max_bytes: Optional[Int] = none) -> Result[Logger, LogError]:
```

## file_transport {data-api-kind="Function"}

```manuscript
fn file_transport(path: String) -> Result[Transport, LogError]:
```

## stdout_transport {data-api-kind="Function"}

```manuscript
fn stdout_transport() -> Transport:
```

## stream_transport {data-api-kind="Function"}

```manuscript
fn stream_transport(output: WriteStream) -> Transport:
```

