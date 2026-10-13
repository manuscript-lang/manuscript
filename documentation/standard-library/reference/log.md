+++
title = "log"
+++

# @std/log.ms

Import each required symbol with `import Name from "@std/log.ms"`.

## LogError {data-api-kind="Alternative"}

Errors returned while validating or writing a structured log record.

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

Severity levels accepted by a logger, ordered from Trace through Fatal.

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

A structured logger with level filtering, bound fields, and pluggable transports.

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

A destination that accepts encoded log records and can be flushed and closed.

```manuscript
interface Transport:
    fn write(data: Bytes) -> Result[Unit, LogError]
    fn flush() -> Result[Unit, LogError]
    fn close() -> Unit
```

## create {data-api-kind="Function"}

Creates a logger. Defaults to `Info`, no bound fields, timestamps enabled, and no record-size limit.

```manuscript
fn create(transport: Transport, level: Optional[LogLevel] = none, bindings: Optional[Map[String, JsonValue]] = none, timestamp: Optional[Bool] = none, max_bytes: Optional[Int] = none) -> Result[Logger, LogError]:
```

## file_transport {data-api-kind="Function"}

Appends log records to a file at `path`.

```manuscript
fn file_transport(path: String) -> Result[Transport, LogError]:
```

## stdout_transport {data-api-kind="Function"}

Writes log records to the process standard-output stream.

```manuscript
fn stdout_transport() -> Transport:
```

## stream_transport {data-api-kind="Function"}

Writes log records to an existing byte stream.

```manuscript
fn stream_transport(output: WriteStream) -> Transport:
```

