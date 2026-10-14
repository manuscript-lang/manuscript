# Canonical standard-library declarations. Implementations are native.

import IoError from "@std/io.ms"
import WriteStream from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import JsonValue from "@std/json.ms"
import FileSystemError from "@std/fs.ms"

# Errors returned while validating or writing a structured log record.
export type LogError:
    # The selected record level or an explicit record-size budget is invalid.
    case InvalidInput
    # Structured fields cannot be encoded as valid JSON, including cyclic values.
    case InvalidData
    # The JSON record plus its terminating newline exceeds the supplied byte budget.
    case LimitExceeded
    # The native transport has closed, so an admitted write or flush cannot complete.
    case Closed
    # A transport's underlying byte-stream operation returned its original I/O error.
    case Io(
        # Original stream error; its message and concrete case are preserved.
        cause: IoError
    )
    # Opening the owned file transport returned a filesystem error.
    case FileSystem(
        # Original filesystem error retained from file acquisition.
        cause: FileSystemError
    )

# Severity levels accepted by a logger, ordered from Trace through Fatal.
export type LogLevel:
    # Most detailed records, encoded with numeric level 10.
    case Trace
    # Development diagnostics, encoded with numeric level 20.
    case Debug
    # Ordinary operational records, encoded with numeric level 30; the default threshold.
    case Info
    # Warning records, encoded with numeric level 40.
    case Warn
    # Failure records, encoded with numeric level 50.
    case Error
    # Critical records at numeric level 60; logging does not terminate the process.
    case Fatal
    # Filtering threshold that disables records; passing it to log returns InvalidInput.
    case Silent

# A destination that accepts encoded log records and can be flushed and closed.
export interface Transport:
    # Accepts encoded record bytes; native transports serialize writes and may return the original I/O cause.
    # Errors can follow a partial external write, without rollback.
    fn write(data: Bytes) -> Result[Unit, LogError]
    # Delegates flush to the destination; persistence and buffering depend on that destination.
    fn flush() -> Result[Unit, LogError]
    # Releases owned resources; native close cancels admitted operations and leaves borrowed streams open.
    fn close() -> Unit

# A structured logger with level filtering, bound fields, and pluggable transports.
export interface Logger:
    # Writes a record at the selected level with optional JSON fields.
    fn log(
        level: LogLevel,
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    # Logs at Trace when enabled; a filtered call returns ok without encoding or transport access.
    fn trace(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    # Logs at Debug when enabled, with call fields overriding child bindings for duplicate keys.
    fn debug(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    # Logs at Info when enabled; reserved level, msg, and time fields remain controlled by the logger.
    fn info(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    # Logs at Warn when enabled, returning encoding, size-budget, or transport errors unchanged.
    fn warn(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    # Logs at Error when enabled; it records an expected diagnostic rather than raising a fault.
    fn error(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    # Logs at Fatal when enabled; the caller remains responsible for process termination.
    fn fatal(
        message: String,
        fields: Optional[Map[String, JsonValue]] = none
    ) -> Result[Unit, LogError]
    # Tests the current filtering threshold; Silent is never enabled as a record level.
    fn enabled(level: LogLevel) -> Bool
    # Returns this logger's current threshold, independent of its parent or children.
    fn level() -> LogLevel
    # Changes only this logger's threshold; existing child loggers retain their copied threshold.
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
    max_bytes: Optional[Int] = none
) -> Result[Logger, LogError]:

# Writes log records to an existing byte stream.
export fn stream_transport(output: WriteStream) -> Transport:

# Writes log records to the process standard-output stream.
export fn stdout_transport() -> Transport:

# Appends log records to a file at `path`.
export fn file_transport(path: String) -> Result[Transport, LogError]:

impl Error for LogError:
    # Returns the preserved I/O/filesystem cause message, or a logging-prefixed diagnostic.
    fn message() -> String:
