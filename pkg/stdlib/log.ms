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

# documentation documentation/standard-library/logging.md
# +++
# title = "Logging"
# weight = 18
# +++
#
# # Logging
#
# API reference: [log](reference/log.md).
#
# Import `create` and a transport from `@std/log.ms`. A logger combines level filtering, structured JSON fields, and reusable context. Transports send complete records to stdout, an append-only file, or a supplied `WriteStream`. Logging failures are returned as `Result` errors.
#
# ## Write a record
#
# This complete program writes one JSON line to stdout. `try` propagates logging failures through the standard `Error` boundary.
#
# <!-- manuscript-example: {"mode":"run","stdout":"{\"level\":30,\"msg\":\"listening\",\"port\":8080}\n"} -->
# ```manuscript
# import {create, stdout_transport} from "@std/log.ms"
# import JsonValue from "@std/json.ms"
#
# fn announce() -> Result[Unit, Error]:
#     with transport = stdout_transport():
#         let logger = try create(transport: transport, timestamp: false)
#         let fields = Map[String, JsonValue]().add(
#             key: "port",
#             value: JsonValue.NumberValue("8080")
#         )
#         let written = try logger.info(message: "listening", fields: fields)
#         return ok(unit)
#
# export fn main() -> Int:
#     match announce():
#         ok(_): return 0
#         error(_): return 1
# ```
#
# `fields` is optional; `logger.info(message: "started")` emits a message without additional fields. JSON fields support null, booleans, exact numbers, strings, arrays, and nested objects through `JsonValue`. See the [JSON reference](reference/json.md) for construction and parsing. Invalid numeric text or cyclic JSON values return `LogError.InvalidData` before the transport receives data.
#
# Each record is compact UTF-8 JSON followed by LF. The top-level envelope contains numeric `level`, `msg`, and, by default, `time` as Unix epoch milliseconds. Additional fields appear at the top level in map insertion order. The envelope owns `level`, `msg`, and `time`; supplied bindings or fields with those keys are ignored, including `time` when timestamps are disabled. Embedded newlines and quotes are escaped, keeping one record per physical line.
#
# ## Levels and context
#
# `trace`, `debug`, `info`, `warn`, `error`, and `fatal` return `Result[Unit, LogError]`. Their levels are 10, 20, 30, 40, 50, and 60 respectively. `log(level: level, message: message, fields: fields)` selects a method's level dynamically. `LogLevel.Silent` is a filtering threshold; using it as a record level returns `InvalidInput`. `fatal` emits a record and leaves process termination to the caller.
#
# The default threshold is `LogLevel.Info`. Pass `level: LogLevel.Debug` to `create`, or use `logger.set_level(LogLevel.Debug)` later. `logger.level()` returns the current threshold and `logger.enabled(LogLevel.Debug)` checks whether that level passes it. `LogLevel.Silent` disables all logging. Filtered calls return `ok(unit)` without serialization or transport access, even if the transport is closed; arguments still evaluate normally.
#
# Pass `bindings: bindings` to `create` for persistent fields. `logger.child(bindings)` makes a logger with extra context and the parent's current threshold, timestamp setting, record limit, and transport. Parent level changes do not change existing children. Bindings merge in parent → child → per-call order; later values win. Construction and child creation copy top-level map membership, preserving ordinary references to nested JSON collections. Logging does not mutate supplied maps. Synchronize externally if nested collections are modified concurrently.
#
# ## Transports and cleanup
#
# - `stdout_transport()` borrows the host stdout stream.
# - `stream_transport(output)` borrows a supplied `WriteStream`, including a source implementation for testing or integration.
# - `file_transport(path)` opens or creates a file for append with mode `0600` for newly created files, subject to the host umask. It owns that file. Parent directories must already exist. Open failures return `LogError.FileSystem(cause)` with the original `FileSystemError`.
#
# Use `with` to close transports. Loggers and their children share the transport but do not own it. Closing a borrowed transport leaves its underlying stream open; closing a file transport releases its file handle. Close is idempotent, ends admission, cancels active operations, and joins admitted calls. Later transport writes and flushes return `LogError.Closed`. Source streams must cooperate with cancellation to make interrupted operations finish.
#
# Transports serialize complete writes and apply backpressure synchronously. They do not queue records in the background. `logger.flush()` delegates to the transport; file flush synchronizes the file to disk, while stdout uses the host stream's flush. Check flush results when persistence matters. Closing is cleanup, not an implicit successful flush. A write failure may follow a partial external write; no rollback is promised. Stream failures preserve their `IoError` as `LogError.Io(cause)`.
#
# For file logging, replace the stdout acquisition in the example with `with transport = try file_transport("events.ndjson"):` and import `file_transport`.
#
# A custom transport implements the ordinary `Transport` interface: `write(data: Bytes) -> Result[Unit, LogError]`, `flush() -> Result[Unit, LogError]`, and `close() -> Unit`. Construct its explicit `Transport(value: implementation)` view and pass it to `create`. Custom implementations own their synchronization and lifecycle behavior.
#
# ## Record limits
#
# `create` accepts `max_bytes: Optional[Int] = none`. Omission or `none` imposes no record limit. A supplied nonnegative limit counts the entire UTF-8 JSON line, including LF. An exact fit succeeds. Excess returns `LimitExceeded` before writing, and a negative limit returns `InvalidInput` during creation. A zero limit rejects every enabled record. Filtering happens before the record budget is checked.
#
# The caller chooses fields and their sensitivity; automatic redaction and object inspection are not part of this API. Bound untrusted inputs when necessary: serialization checks the supplied output budget, but the input collections and escaped string temporaries may already occupy memory.
# end-documentation
