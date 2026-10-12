# Canonical standard-library declarations. Implementations are native.

import Optional from "@std/optional.ms"
import Error from "@std/errors.ms"
import IoError from "@std/io.ms"
import Map from "@std/collections.ms"
import Result from "@std/result.ms"
import WriteStream from "@std/io.ms"
import Bytes from "@std/bytes.ms"
import JsonValue from "@std/json.ms"
import FileSystemError from "@std/fs.ms"

export type LogError:
    case InvalidInput
    case InvalidData
    case LimitExceeded
    case Closed
    case Io(cause: IoError)
    case FileSystem(cause: FileSystemError)

export type LogLevel:
    case Trace
    case Debug
    case Info
    case Warn
    case Error
    case Fatal
    case Silent

export interface Transport:
    fn write(data: Bytes) -> Result[Unit, LogError]
    fn flush() -> Result[Unit, LogError]
    fn close() -> Unit

export interface Logger:
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
    fn child(bindings: Map[String, JsonValue]) -> Logger
    fn flush() -> Result[Unit, LogError]

export fn create(
    transport: Transport,
    level: Optional[LogLevel] = none,
    bindings: Optional[Map[String, JsonValue]] = none,
    timestamp: Optional[Bool] = none,
    max_bytes: Optional[Int] = none
) -> Result[Logger, LogError]:

export fn stream_transport(output: WriteStream) -> Transport:

export fn stdout_transport() -> Transport:

export fn file_transport(path: String) -> Result[Transport, LogError]:

impl Error for LogError:
    fn message() -> String:
