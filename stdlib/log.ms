import Data from "@std/core.ms"
import IoError from "@std/io/io.ms"
import WriteStream from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import Shared from "@std/concurrency/shared.ms"
import FileHandle, FileSystemError, open from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"
import stringify from "@std/data/json.ms"
import now from "@std/os/time.ms"
import LogCoreError, LogGate, LogState, new_gate, new_state, object_text from "@std/logcore.ms"

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
    # Accepts encoded record bytes and may return the original I/O cause. Errors can follow a partial
    # external write, without rollback. Child loggers call a shared transport concurrently, so an
    # implementation that keeps mutable state guards it itself, as the standard transports do.
    var fn write(data: String) Unit!LogError
    # Accepts encoded record bytes with the same rules as write.
    var fn write_bytes(data: Bytes) Unit!LogError
    # Delegates flush to the destination; persistence and buffering depend on that destination.
    var fn flush() Unit!LogError
    # Releases owned resources; native close cancels admitted operations and leaves borrowed streams open.
    var fn close() Unit

# Level indexes shared with the encoder: Trace is 0 and Silent is 6.
fn level_index(level: LogLevel) Int:
    match level:
        Trace: return 0
        Debug: return 1
        Info: return 2
        Warn: return 3
        Error: return 4
        Fatal: return 5
        Silent: return 6

fn level_at(index: Int) LogLevel:
    if index == 0: return LogLevel.Trace
    if index == 1: return LogLevel.Debug
    if index == 2: return LogLevel.Info
    if index == 3: return LogLevel.Warn
    if index == 4: return LogLevel.Error
    if index == 5: return LogLevel.Fatal

    return LogLevel.Silent

fn core_error(cause: LogCoreError) LogError:
    if cause == LogCoreError.InvalidInput: return LogError.InvalidInput
    if cause == LogCoreError.LimitExceeded: return LogError.LimitExceeded

    return LogError.InvalidData

# Milliseconds since the Unix epoch, the unit of the `time` field.
fn now_ms() Int:
    let now = now()
    return now.unix_seconds() * 1000 + now.nanoseconds() / 1000000

# Writes to a byte stream the caller owns; closing the transport leaves the stream open.
type StreamTransport:
    stream: Shared[WriteStream]
    gate: LogGate

impl Transport for StreamTransport:
    var fn write(data: String) Unit!LogError:
        if self.gate.is_shut(): return error(LogError.Closed)

        match self.stream.write(data):
            ok(_): return ok(unit)
            error(cause): return error(LogError.Io(cause))

    var fn write_bytes(data: Bytes) Unit!LogError:
        if self.gate.is_shut(): return error(LogError.Closed)

        match self.stream.write_bytes(data):
            ok(_): return ok(unit)
            error(cause): return error(LogError.Io(cause))

    var fn flush() Unit!LogError:
        if self.gate.is_shut(): return error(LogError.Closed)

        match self.stream.flush():
            ok(_): return ok(unit)
            error(cause): return error(LogError.Io(cause))

    var fn close() Unit:
        self.gate.shut()

# Appends to a file the transport opened, and closes it with the transport.
type FileTransport:
    file: Shared[FileHandle]
    inner: StreamTransport

impl Transport for FileTransport:
    var fn write(data: String) Unit!LogError:
        return self.inner.write(data)

    var fn write_bytes(data: Bytes) Unit!LogError:
        return self.inner.write_bytes(data)

    var fn flush() Unit!LogError:
        return self.inner.flush()

    var fn close() Unit:
        if not self.inner.gate.is_shut():
            self.inner.close()
            self.file.close().get(none)

# A structured logger: level filtering, bound fields, and a pluggable `Transport`. The `_with` methods
# take fields of any `Data` type and encode them with `stringify`. Child loggers share the transport;
# closing any of them closes it for all.
export type Logger:
    # Internal state: level threshold, bound fields and the record encoder.
    state: LogState
    # Internal state: the transport this logger and its children write to.
    transport: Shared[Transport]

impl Logger:
    # Internal: encodes a plain record at a level index and sends it.
    var fn emit(level: Int, message: String) Unit!LogError:
        let encoded = self.state.line(level, message, now_ms())
        if encoded.is_error(): return error(core_error(encoded.err()))

        return self.send(encoded.get())

    # Internal: encodes a record with fields given as JSON object text and sends it.
    var fn emit_json(level: Int, message: String, fields: String) Unit!LogError:
        let encoded = self.state.line_json(level, message, fields, now_ms())
        if encoded.is_error(): return error(core_error(encoded.err()))

        return self.send(encoded.get())

    # Internal: a filtered record encodes to no text and never reaches the transport.
    var fn send(text: String) Unit!LogError:
        if text == "": return ok(unit)

        return self.transport.write(text)

    # Writes a record whose fields come from `fields`, which can be any value `stringify` accepts.
    #
    # A record, map, or `JsonValue` object contributes its members at the top level of the record.
    # Any other value, such as a number, string, list, or `none`, is written under the key `data`.
    # A value that cannot be encoded, such as a cyclic one, returns `InvalidData`; encoding happens
    # only when the level is enabled. The reserved keys `level`, `msg`, and `time` are ignored.
    var fn log_with[F: Data](level: LogLevel, message: String, fields: F) Unit!LogError:
        if level == LogLevel.Silent: return error(LogError.InvalidInput)
        if not self.enabled(level): return ok(unit)

        let text = stringify(fields)
        if text.is_error(): return error(LogError.InvalidData)

        return self.emit_json(level_index(level), message, object_text(text.get()))

    # Like `trace`, with fields of any `Data` type; see `log_with` for how they are encoded.
    var fn trace_with[F: Data](message: String, fields: F) Unit!LogError:
        return self.log_with(LogLevel.Trace, message, fields)

    # Like `debug`, with fields of any `Data` type; see `log_with` for how they are encoded.
    var fn debug_with[F: Data](message: String, fields: F) Unit!LogError:
        return self.log_with(LogLevel.Debug, message, fields)

    # Like `info`, with fields of any `Data` type; see `log_with` for how they are encoded.
    var fn info_with[F: Data](message: String, fields: F) Unit!LogError:
        return self.log_with(LogLevel.Info, message, fields)

    # Like `warn`, with fields of any `Data` type; see `log_with` for how they are encoded.
    var fn warn_with[F: Data](message: String, fields: F) Unit!LogError:
        return self.log_with(LogLevel.Warn, message, fields)

    # Like `error`, with fields of any `Data` type; see `log_with` for how they are encoded.
    var fn error_with[F: Data](message: String, fields: F) Unit!LogError:
        return self.log_with(LogLevel.Error, message, fields)

    # Like `fatal`, with fields of any `Data` type; see `log_with` for how they are encoded.
    var fn fatal_with[F: Data](message: String, fields: F) Unit!LogError:
        return self.log_with(LogLevel.Fatal, message, fields)

    # Returns a logger that adds the members of `fields` to each record, with the encoding rules of
    # `log_with`. A value that cannot be encoded returns `InvalidData`.
    fn child[F: Data](fields: F) Logger!LogError:
        let text = stringify(fields)
        if text.is_error(): return error(LogError.InvalidData)

        let child = try self.state.child(object_text(text.get())).map_error(core_error)
        return ok(Logger(child, self.transport))

impl Logger:
    # Writes a record at the selected level with no fields.
    var fn log(level: LogLevel, message: String) Unit!LogError:
        return self.emit(level_index(level), message)

    # Logs at Trace when enabled; a filtered call returns ok without encoding or transport access.
    var fn trace(message: String) Unit!LogError:
        return self.emit(0, message)

    # Logs at Debug when enabled, including the logger's bound fields.
    var fn debug(message: String) Unit!LogError:
        return self.emit(1, message)

    # Logs at Info when enabled; reserved level, msg, and time fields remain controlled by the logger.
    var fn info(message: String) Unit!LogError:
        return self.emit(2, message)

    # Logs at Warn when enabled, returning encoding, size-budget, or transport errors unchanged.
    var fn warn(message: String) Unit!LogError:
        return self.emit(3, message)

    # Logs at Error when enabled; it records an expected diagnostic rather than raising a fault.
    var fn error(message: String) Unit!LogError:
        return self.emit(4, message)

    # Logs at Fatal when enabled; the caller remains responsible for process termination.
    var fn fatal(message: String) Unit!LogError:
        return self.emit(5, message)

    # Tests the current filtering threshold; Silent is never enabled as a record level.
    fn enabled(level: LogLevel) Bool:
        return self.state.enabled(level_index(level))

    # Returns this logger's current threshold, independent of its parent or children.
    fn level() LogLevel:
        return level_at(self.state.level())

    # Changes only this logger's threshold; existing child loggers retain their copied threshold.
    var fn set_level(level: LogLevel) Unit:
        self.state.set_level(level_index(level))

    # Flushes the logger's transport.
    var fn flush() Unit!LogError:
        return self.transport.flush()

    # Closes the transport this logger shares with its children, so every one of them reports `Closed`
    # afterwards. A scope that owns the logger calls it on every exit.
    var fn close() Unit:
        self.transport.close()

# Creates a logger that owns `transport`. Defaults to `Info`, timestamps enabled, and no record-size limit.
export fn create(
    transport: Transport,
    level: LogLevel?,
    timestamp: Bool?,
    max_bytes: Int?
) Logger!LogError:
    var index: Int? = none
    if let chosen = level:
        index = level_index(chosen)

    let state = try new_state(index, timestamp, max_bytes).map_error(core_error)
    return ok(Logger(state, Shared(transport)))

# Writes log records to an existing byte stream.
export fn stream_transport(output: WriteStream) Transport:
    return StreamTransport(Shared(output), new_gate())

# Writes log records to the process standard-output stream.
export fn stdout_transport() Transport:
    return stream_transport(stdout())

# Appends log records to a file at `path`.
export fn file_transport(path: String) Transport!LogError:
    match open(path, "a", 420):
        ok(file): return ok(file_stream_transport(file))
        error(cause): return error(LogError.FileSystem(cause))

fn file_stream_transport(file: FileHandle) Transport:
    let stream = StreamTransport(Shared(file.writer()), new_gate())
    return FileTransport(Shared(file), stream)

impl Error for LogError:
    # Returns the preserved I/O/filesystem cause message, or a logging-prefixed diagnostic.
    fn message() String:
        match self:
            InvalidInput: return "logging: invalid input"
            InvalidData: return "logging: invalid data"
            LimitExceeded: return "logging: limit exceeded"
            Closed: return "logging: resource is closed"
            Io(cause): return cause.message()
            FileSystem(cause): return cause.message()
