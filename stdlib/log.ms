from "@std/io.ms" import IoError
from "@std/io.ms" import WriteStream
from "@std/bytes.ms" import Bytes
from "@std/shared.ms" import Shared, share
from "@std/sync.ms" import lock
from "@std/fs.ms" import FileHandle, FileSystemError, filesystem
from "@std/io.ms" import stdout
from "@std/json.ms" import stringify
from "@std/time.ms" import wall_clock
from "@std/logcore.ms" import LogCoreError, LogGate, LogState, new_gate, new_state, object_text

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
    var def write(data: String) -> Result[Unit, LogError]
    # Accepts encoded record bytes with the same rules as write.
    var def write_bytes(data: Bytes) -> Result[Unit, LogError]
    # Delegates flush to the destination; persistence and buffering depend on that destination.
    var def flush() -> Result[Unit, LogError]
    # Releases owned resources; native close cancels admitted operations and leaves borrowed streams open.
    var def close() -> Unit

# A structured logger with level filtering, bound fields, and pluggable transports.
#
# Methods that take only a message write a record without fields. To attach fields of any
# type, use `record` and `bind`, which encode the value with `stringify`.
export interface Logger:
    # Writes a record at the selected level with no fields.
    def log(level: LogLevel, message: String) -> Result[Unit, LogError]
    # Logs at Trace when enabled; a filtered call returns ok without encoding or transport access.
    def trace(message: String) -> Result[Unit, LogError]
    # Logs at Debug when enabled, including the logger's bound fields.
    def debug(message: String) -> Result[Unit, LogError]
    # Logs at Info when enabled; reserved level, msg, and time fields remain controlled by the logger.
    def info(message: String) -> Result[Unit, LogError]
    # Logs at Warn when enabled, returning encoding, size-budget, or transport errors unchanged.
    def warn(message: String) -> Result[Unit, LogError]
    # Logs at Error when enabled; it records an expected diagnostic rather than raising a fault.
    def error(message: String) -> Result[Unit, LogError]
    # Logs at Fatal when enabled; the caller remains responsible for process termination.
    def fatal(message: String) -> Result[Unit, LogError]
    # Writes a record whose fields are the members of `fields`, a JSON object in text form.
    # Text that is not a JSON object returns `InvalidData`. Prefer `record`, which builds the text.
    def log_json(
        level: LogLevel,
        message: String,
        fields: String
    ) -> Result[Unit, LogError]
    # Returns a logger that adds the members of `fields`, a JSON object in text form, to each
    # record. Text that is not a JSON object returns `InvalidData`. Prefer `bind`.
    def child_json(fields: String) -> Result[Logger, LogError]
    # Tests the current filtering threshold; Silent is never enabled as a record level.
    def enabled(level: LogLevel) -> Bool
    # Returns this logger's current threshold, independent of its parent or children.
    def level() -> LogLevel
    # Changes only this logger's threshold; existing child loggers retain their copied threshold.
    def set_level(level: LogLevel) -> Unit
    # Flushes the logger's transport.
    def flush() -> Result[Unit, LogError]
    # Closes the transport this logger shares with its children, so every one of them reports `Closed`
    # afterwards. A `with` binding calls it on every exit.
    var def close() -> Unit

# Level indexes shared with the encoder: Trace is 0 and Silent is 6.
def level_index(level: LogLevel) -> Int:
    match level:
        case Trace: return 0
        case Debug: return 1
        case Info: return 2
        case Warn: return 3
        case Error: return 4
        case Fatal: return 5
        case Silent: return 6

def level_at(index: Int) -> LogLevel:
    if index == 0: return LogLevel.Trace
    if index == 1: return LogLevel.Debug
    if index == 2: return LogLevel.Info
    if index == 3: return LogLevel.Warn
    if index == 4: return LogLevel.Error
    if index == 5: return LogLevel.Fatal

    return LogLevel.Silent

def core_error(cause: LogCoreError) -> LogError:
    if cause == LogCoreError.InvalidInput: return LogError.InvalidInput
    if cause == LogCoreError.LimitExceeded: return LogError.LimitExceeded

    return LogError.InvalidData

# Milliseconds since the Unix epoch, the unit of the `time` field.
def now_ms() -> Int:
    let now = wall_clock().now()
    return now.unix_seconds() * 1000 + now.nanoseconds() / 1000000

# Writes to a byte stream the caller owns; closing the transport leaves the stream open.
type StreamTransport:
    stream: WriteStream
    gate: LogGate

impl Transport for StreamTransport:
    var def write(data: String) -> Result[Unit, LogError]:
        if self.gate.is_shut(): return error(LogError.Closed)

        match self.stream.write(data):
            case ok(_): return ok(())
            case error(cause): return error(LogError.Io(cause))

    var def write_bytes(data: Bytes) -> Result[Unit, LogError]:
        if self.gate.is_shut(): return error(LogError.Closed)

        match self.stream.write_bytes(data):
            case ok(_): return ok(())
            case error(cause): return error(LogError.Io(cause))

    var def flush() -> Result[Unit, LogError]:
        if self.gate.is_shut(): return error(LogError.Closed)

        match self.stream.flush():
            case ok(_): return ok(())
            case error(cause): return error(LogError.Io(cause))

    var def close() -> Unit:
        self.gate.shut()

# Appends to a file the transport opened, and closes it with the transport.
type FileTransport:
    file: FileHandle
    inner: StreamTransport

impl Transport for FileTransport:
    var def write(data: String) -> Result[Unit, LogError]:
        return self.inner.write(data)

    var def write_bytes(data: Bytes) -> Result[Unit, LogError]:
        return self.inner.write_bytes(data)

    var def flush() -> Result[Unit, LogError]:
        return self.inner.flush()

    var def close() -> Unit:
        if not self.inner.gate.is_shut():
            self.inner.close()
            self.file.close()

# The logger behind the `Logger` interface: shared encoder state plus the transport it writes to.
type StdLogger:
    state: LogState
    transport: Shared[Transport]

impl StdLogger:
    def emit(level: Int, message: String) -> Result[Unit, LogError]:
        let encoded = self.state.line(level, message, now_ms())
        if encoded.is_error(): return error(core_error(encoded.err()))

        return self.send(encoded.get())

    def emit_json(level: Int, message: String, fields: String) -> Result[Unit, LogError]:
        let encoded = self.state.line_json(level, message, fields, now_ms())
        if encoded.is_error(): return error(core_error(encoded.err()))

        return self.send(encoded.get())

    # A filtered record encodes to no text and never reaches the transport.
    def send(text: String) -> Result[Unit, LogError]:
        if text == "": return ok(())

        var transport = lock(self.transport)
        return transport.value.write(text)

impl Logger for StdLogger:
    def log(level: LogLevel, message: String) -> Result[Unit, LogError]:
        return self.emit(level_index(level), message)

    def trace(message: String) -> Result[Unit, LogError]:
        return self.emit(0, message)

    def debug(message: String) -> Result[Unit, LogError]:
        return self.emit(1, message)

    def info(message: String) -> Result[Unit, LogError]:
        return self.emit(2, message)

    def warn(message: String) -> Result[Unit, LogError]:
        return self.emit(3, message)

    def error(message: String) -> Result[Unit, LogError]:
        return self.emit(4, message)

    def fatal(message: String) -> Result[Unit, LogError]:
        return self.emit(5, message)

    def log_json(
        level: LogLevel,
        message: String,
        fields: String
    ) -> Result[Unit, LogError]:
        return self.emit_json(level_index(level), message, fields)

    def child_json(fields: String) -> Result[Logger, LogError]:
        let child = self.state.child(fields)
        if child.is_error(): return error(core_error(child.err()))

        return ok(StdLogger(child.get(), self.transport))

    def enabled(level: LogLevel) -> Bool:
        return self.state.enabled(level_index(level))

    def level() -> LogLevel:
        return level_at(self.state.level())

    def set_level(level: LogLevel) -> Unit:
        self.state.set_level(level_index(level))

    def flush() -> Result[Unit, LogError]:
        var transport = lock(self.transport)
        return transport.value.flush()

    var def close() -> Unit:
        var transport = lock(self.transport)
        transport.value.close()

# Writes a record whose fields come from `fields`, which can be any value `stringify` accepts.
#
# A record, map, or `JsonValue` object contributes its members at the top level of the record.
# Any other value, such as a number, string, list, or `none`, is written under the key `data`.
# A value that cannot be encoded, such as a cyclic one, returns `InvalidData`; encoding happens
# only when the level is enabled. The reserved keys `level`, `msg`, and `time` are ignored.
export def record[T](
    logger: Logger,
    level: LogLevel,
    message: String,
    fields: T
) -> Result[Unit, LogError]:
    if level == LogLevel.Silent: return error(LogError.InvalidInput)
    if not logger.enabled(level): return ok(())

    let text = stringify(fields)
    if text.is_error(): return error(LogError.InvalidData)

    return logger.log_json(level, message, object_text(text.get()))

# Creates a logger that owns `transport`. Defaults to `Info`, timestamps enabled, and no record-size limit.
# Child loggers from `child_json` share the transport; closing any of them (`with logger = create(...)`
# closes on every exit) closes it for all.
export def create(
    transport: Transport,
    level: Optional[LogLevel] = none,
    timestamp: Optional[Bool] = none,
    max_bytes: Optional[Int] = none
) -> Result[Logger, LogError]:
    var index: Optional[Int] = none
    if let chosen = level:
        index = level_index(chosen)

    let state = new_state(index, timestamp, max_bytes)
    if state.is_error(): return error(core_error(state.err()))

    return ok(StdLogger(state.get(), share(transport)))

# Writes log records to an existing byte stream.
export def stream_transport(output: WriteStream) -> Transport:
    return StreamTransport(output, new_gate())

# Writes log records to the process standard-output stream.
export def stdout_transport() -> Transport:
    return stream_transport(stdout())

# Appends log records to a file at `path`.
export def file_transport(path: String) -> Result[Transport, LogError]:
    match filesystem().open(path, "a", 420):
        case ok(file): return ok(file_stream_transport(file))
        case error(cause): return error(LogError.FileSystem(cause))

def file_stream_transport(file: FileHandle) -> Transport:
    let stream = StreamTransport(file.writer(), new_gate())
    return FileTransport(file, stream)

impl Error for LogError:
    # Returns the preserved I/O/filesystem cause message, or a logging-prefixed diagnostic.
    def message() -> String:
        match self:
            case InvalidInput: return "logging: invalid input"
            case InvalidData: return "logging: invalid data"
            case LimitExceeded: return "logging: limit exceeded"
            case Closed: return "logging: resource is closed"
            case Io(cause): return cause.message()
            case FileSystem(cause): return cause.message()
