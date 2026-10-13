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

### LogError.Closed

The native transport has closed, so an admitted write or flush cannot complete.

```manuscript
case Closed
```

### LogError.FileSystem

Opening the owned file transport returned a filesystem error.

```manuscript
case FileSystem(cause: FileSystemError)
```

### LogError.InvalidData

Structured fields cannot be encoded as valid JSON, including cyclic values.

```manuscript
case InvalidData
```

### LogError.InvalidInput

The selected record level or an explicit record-size budget is invalid.

```manuscript
case InvalidInput
```

### LogError.Io

A transport's underlying byte-stream operation returned its original I/O error.

```manuscript
case Io(cause: IoError)
```

### LogError.LimitExceeded

The JSON record plus its terminating newline exceeds the supplied byte budget.

```manuscript
case LimitExceeded
```

### LogError.FileSystem.cause

Original filesystem error retained from file acquisition.

```manuscript
cause: FileSystemError
```

### LogError.Io.cause

Original stream error; its message and concrete case are preserved.

```manuscript
cause: IoError
```

### LogError.Error.message

Returns the preserved I/O/filesystem cause message, or a logging-prefixed diagnostic.

```manuscript
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

### LogLevel.Debug

Development diagnostics, encoded with numeric level 20.

```manuscript
case Debug
```

### LogLevel.Error

Failure records, encoded with numeric level 50.

```manuscript
case Error
```

### LogLevel.Fatal

Critical records at numeric level 60; logging does not terminate the process.

```manuscript
case Fatal
```

### LogLevel.Info

Ordinary operational records, encoded with numeric level 30; the default threshold.

```manuscript
case Info
```

### LogLevel.Silent

Filtering threshold that disables records; passing it to log returns InvalidInput.

```manuscript
case Silent
```

### LogLevel.Trace

Most detailed records, encoded with numeric level 10.

```manuscript
case Trace
```

### LogLevel.Warn

Warning records, encoded with numeric level 40.

```manuscript
case Warn
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

### Logger.child

Returns a logger that adds these fields to each record.

```manuscript
fn child(bindings: Map[String, JsonValue]) -> Logger
```

### Logger.debug

Logs at Debug when enabled, with call fields overriding child bindings for duplicate keys.

```manuscript
fn debug(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
```

### Logger.enabled

Tests the current filtering threshold; Silent is never enabled as a record level.

```manuscript
fn enabled(level: LogLevel) -> Bool
```

### Logger.error

Logs at Error when enabled; it records an expected diagnostic rather than raising a fault.

```manuscript
fn error(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
```

### Logger.fatal

Logs at Fatal when enabled; the caller remains responsible for process termination.

```manuscript
fn fatal(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
```

### Logger.flush

Flushes the logger's transport.

```manuscript
fn flush() -> Result[Unit, LogError]
```

### Logger.info

Logs at Info when enabled; reserved level, msg, and time fields remain controlled by the logger.

```manuscript
fn info(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
```

### Logger.level

Returns this logger's current threshold, independent of its parent or children.

```manuscript
fn level() -> LogLevel
```

### Logger.log

Writes a record at the selected level with optional JSON fields.

```manuscript
fn log(level: LogLevel, message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
```

### Logger.set_level

Changes only this logger's threshold; existing child loggers retain their copied threshold.

```manuscript
fn set_level(level: LogLevel) -> Unit
```

### Logger.trace

Logs at Trace when enabled; a filtered call returns ok without encoding or transport access.

```manuscript
fn trace(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
```

### Logger.warn

Logs at Warn when enabled, returning encoding, size-budget, or transport errors unchanged.

```manuscript
fn warn(message: String, fields: Optional[Map[String, JsonValue]] = none) -> Result[Unit, LogError]
```

## Transport {data-api-kind="Interface"}

A destination that accepts encoded log records and can be flushed and closed.

```manuscript
interface Transport:
    fn write(data: Bytes) -> Result[Unit, LogError]
    fn flush() -> Result[Unit, LogError]
    fn close() -> Unit
```

### Transport.close

Releases owned resources; native close cancels admitted operations and leaves borrowed streams open.

```manuscript
fn close() -> Unit
```

### Transport.flush

Delegates flush to the destination; persistence and buffering depend on that destination.

```manuscript
fn flush() -> Result[Unit, LogError]
```

### Transport.write

Accepts encoded record bytes; native transports serialize writes and may return the original I/O cause.
Errors can follow a partial external write, without rollback.

```manuscript
fn write(data: Bytes) -> Result[Unit, LogError]
```

## create {data-api-kind="Function"}

Creates a logger. Defaults to `Info`, no bound fields, timestamps enabled, and no record-size limit.

```manuscript
fn create(transport: Transport, level: Optional[LogLevel] = none, bindings: Optional[Map[String, JsonValue]] = none, timestamp: Optional[Bool] = none, max_bytes: Optional[Int64] = none) -> Result[Logger, LogError]:
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

