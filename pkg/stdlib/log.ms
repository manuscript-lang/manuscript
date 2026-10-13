# Canonical standard-library declarations. Implementations are native.

import IoError from "@std/io.ms"
import Map from "@std/collections.ms"
import WriteStream from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import JsonValue from "@std/json.ms"
import FileSystemError from "@std/fs.ms"

# Errors returned while validating or writing a structured log record.
export type LogError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Closed
    case Io(cause: IoError)
    case FileSystem(cause: FileSystemError)

# Severity levels accepted by a logger, ordered from Trace through Fatal.
export type LogLevel:
    case Trace
    case Debug
    case Info
    case Warn
    case Error
    case Fatal
    case Silent

# A destination that accepts encoded log records and can be flushed and closed.
export interface Transport:
    fn write(data: Bytes) -> Result[Unit, LogError]
    fn flush() -> Result[Unit, LogError]
    fn close() -> Unit

# A structured logger with level filtering, bound fields, and pluggable transports.
export interface Logger:
    # Writes a record at the selected level with optional JSON fields.
    fn log(
        level: LogLevel,
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    fn trace(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    fn debug(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    fn info(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    fn warn(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    fn error(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    fn fatal(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    fn enabled(level: LogLevel) -> Bool
    fn level() -> LogLevel
    fn set_level(level: LogLevel) -> Unit
    # Returns a logger that adds these fields to each record.
    fn child(bindings: Map[String, JsonValue]) -> Logger
    # Flushes the logger's transport.
    fn flush() -> Result[Unit, LogError]

# Creates a logger. Defaults to `Info`, no bound fields, timestamps enabled, and no record-size limit.
export fn create(
    transport: Transport,
    level: Optional[LogLevel] = none,
    bindings: Optional[Map[String, JsonValue]] = none,
    timestamp: Optional[Bool] = none,
    max_bytes: Optional[Int64] = none
) -> Result[Logger, LogError]:

# Writes log records to an existing byte stream.
export fn stream_transport(output: WriteStream) -> Transport:

# Writes log records to the process standard-output stream.
export fn stdout_transport() -> Transport:

# Appends log records to a file at `path`.
export fn file_transport(path: String) -> Result[Transport, LogError]:

impl Error for LogError:
    fn message() -> String:
