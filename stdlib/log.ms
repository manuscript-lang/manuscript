import Data from "@std/core.ms"
import IoError from "@std/io/io.ms"
import WriteStream from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import Shared, share from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"
import FileHandle, FileSystemError, open from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"
import JsonError, JsonValue, parse, stringify from "@std/data/json.ms"
import now from "@std/os/time.ms"

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
    fn write(data: String) Unit!LogError
    # Accepts encoded record bytes with the same rules as write.
    fn write_bytes(data: Bytes) Unit!LogError
    # Delegates flush to the destination; persistence and buffering depend on that destination.
    fn flush() Unit!LogError
    # Releases owned resources; native close cancels admitted operations and leaves borrowed streams open.
    fn close() Unit

# The number a level writes into the record's `level` field. Silent is a threshold that no record reaches.
fn level_value(level: LogLevel) Int:
    match level:
        Trace: return 10
        Debug: return 20
        Info: return 30
        Warn: return 40
        Error: return 50
        Fatal: return 60
        Silent: return 70

fn level_at(value: Int) LogLevel:
    if value == 10: return LogLevel.Trace
    if value == 20: return LogLevel.Debug
    if value == 30: return LogLevel.Info
    if value == 40: return LogLevel.Warn
    if value == 50: return LogLevel.Error
    if value == 60: return LogLevel.Fatal

    return LogLevel.Silent

# Milliseconds since the Unix epoch, the unit of the `time` field.
fn now_ms() Int:
    let now = now()
    return now.unix_seconds() * 1000 + now.nanoseconds() / 1000000

# The record envelope owns these keys, so fields cannot replace them.
fn reserved(key: String) Bool:
    return key == "level" or key == "msg" or key == "time"

# The members `fields` contributes to a record: an object's own members, any other value under `data`.
fn members_of(text: String!JsonError) Map[String, JsonValue]!LogError:
    if text.is_error(): return error(LogError.InvalidData)

    let parsed = parse(text.get())
    if parsed.is_error(): return error(LogError.InvalidData)

    let value = parsed.get()
    if let members = value.as_map(): return ok(members)

    var wrapped = Map[String, JsonValue]()
    wrapped.add("data", value)
    return ok(wrapped)

fn encode_error(cause: JsonError) LogError:
    if cause == JsonError.LimitExceeded: return LogError.LimitExceeded

    return LogError.InvalidData

# The open stream of a stream transport and whether the transport was closed.
type StreamState:
    stream: WriteStream
    closed: Bool

# Writes to a byte stream. Child loggers share one transport, so the state is guarded here: the
# logger itself never locks. Closing a transport over a caller's stream leaves the stream open.
type StreamTransport:
    state: Shared[StreamState]

impl Transport for StreamTransport:
    fn write(data: String) Unit!LogError:
        var guard = lock(self.state)
        if guard.value.closed: return error(LogError.Closed)

        match guard.value.stream.write(data):
            ok(_): return ok(unit)
            error(cause): return error(LogError.Io(cause))

    fn write_bytes(data: Bytes) Unit!LogError:
        var guard = lock(self.state)
        if guard.value.closed: return error(LogError.Closed)

        match guard.value.stream.write_bytes(data):
            ok(_): return ok(unit)
            error(cause): return error(LogError.Io(cause))

    fn flush() Unit!LogError:
        var guard = lock(self.state)
        if guard.value.closed: return error(LogError.Closed)

        match guard.value.stream.flush():
            ok(_): return ok(unit)
            error(cause): return error(LogError.Io(cause))

    fn close() Unit:
        let _first = self.shut()

impl StreamTransport:
    # Marks the transport closed and tells whether this call closed it.
    fn shut() Bool:
        var guard = lock(self.state)
        if guard.value.closed: return false

        guard.value.closed = true
        return true

# Appends to a file the transport opened, and closes the file with the transport.
type FileTransport:
    file: Shared[FileHandle]
    inner: StreamTransport

impl Transport for FileTransport:
    fn write(data: String) Unit!LogError:
        return self.inner.write(data)

    fn write_bytes(data: Bytes) Unit!LogError:
        return self.inner.write_bytes(data)

    fn flush() Unit!LogError:
        return self.inner.flush()

    fn close() Unit:
        if self.inner.shut():
            var file = lock(self.file)
            file.value.close().get(none)

# A structured logger: level filtering, bound fields, and a pluggable `Transport`. The level methods
# take optional fields of any `Data` type and encode them with `stringify`. Child loggers share the
# transport; closing any of them closes it for all.
export type Logger:
    # Internal state: the lowest level number that is written.
    threshold: Int
    # Internal state: whether records carry a `time` field.
    timestamp: Bool
    # Internal state: the largest record in bytes including the newline; none is unlimited.
    max_bytes: Int?
    # Internal state: fields added to every record, in insertion order.
    bound: Map[String, JsonValue]
    # Internal state: the transport this logger and its children write to.
    transport: Shared[Transport]

impl Logger:
    # Internal: builds and sends one record at a level number.
    fn emit(level: Int, message: String, fields: Map[String, JsonValue]?) Unit!LogError:
        var record = Map[String, JsonValue]()
        record.add("level", JsonValue.NumberValue("{level}"))
        record.add("msg", JsonValue.StringValue(message))
        if self.timestamp: record.add("time", JsonValue.NumberValue("{now_ms()}"))
        for entry in self.bound.entries():
            if not reserved(entry.key): record.add(entry.key, entry.value.clone())
        if let extra = fields:
            for entry in extra.entries():
                if not reserved(entry.key): record.add(entry.key, entry.value.clone())

        var budget: Int? = none

        if let max = self.max_bytes:
            if max == 0: return error(LogError.LimitExceeded)

            budget = max - 1

        let text = stringify(JsonValue.ObjectValue(record), budget)
        if text.is_error(): return error(encode_error(text.err()))

        return self.transport.get().write("{text.get()}\n")

    # Writes a record at the selected level. `fields` is any `Data` value `stringify` accepts.
    #
    # A record, map, or `JsonValue` object contributes its members at the top level of the record.
    # Any other value, such as a number, string, or list, is written under the key `data`. No
    # fields, or `none`, write the message alone. A value that cannot be encoded, such as a cyclic
    # one, returns `InvalidData`; encoding happens only when the level is enabled. The reserved
    # keys `level`, `msg`, and `time` are ignored. `Silent` is a threshold, not a record level, and
    # returns `InvalidInput`.
    fn log[F: Data = Unit](
        level: LogLevel,
        message: String,
        fields: F? = none
    ) Unit!LogError:
        if level == LogLevel.Silent: return error(LogError.InvalidInput)
        if not self.enabled(level): return ok(unit)

        if let value = fields:
            let members = try members_of(stringify(value))
            return self.emit(level_value(level), message, members)

        return self.emit(level_value(level), message, none)

    # Logs at Trace when enabled. Most detailed records; a filtered call returns ok without encoding or transport access. Fields are encoded as in `log`.
    fn trace[F: Data = Unit](message: String, fields: F? = none) Unit!LogError:
        return self.log(LogLevel.Trace, message, fields)

    # Logs at Debug when enabled. Development diagnostics, including the logger's bound fields. Fields are encoded as in `log`.
    fn debug[F: Data = Unit](message: String, fields: F? = none) Unit!LogError:
        return self.log(LogLevel.Debug, message, fields)

    # Logs at Info when enabled. Ordinary operational records; reserved level, msg, and time fields remain controlled by the logger. Fields are encoded as in `log`.
    fn info[F: Data = Unit](message: String, fields: F? = none) Unit!LogError:
        return self.log(LogLevel.Info, message, fields)

    # Logs at Warn when enabled. Warning records, returning encoding, size-budget, or transport errors unchanged. Fields are encoded as in `log`.
    fn warn[F: Data = Unit](message: String, fields: F? = none) Unit!LogError:
        return self.log(LogLevel.Warn, message, fields)

    # Logs at Error when enabled. Failure records: an expected diagnostic rather than a fault. Fields are encoded as in `log`.
    fn error[F: Data = Unit](message: String, fields: F? = none) Unit!LogError:
        return self.log(LogLevel.Error, message, fields)

    # Logs at Fatal when enabled. Critical records; the caller remains responsible for process termination. Fields are encoded as in `log`.
    fn fatal[F: Data = Unit](message: String, fields: F? = none) Unit!LogError:
        return self.log(LogLevel.Fatal, message, fields)

    # Returns a logger that adds the members of `fields` to each record, with the encoding rules of
    # `log`. A value that cannot be encoded returns `InvalidData`.
    fn child[F: Data](fields: F) Logger!LogError:
        let members = try members_of(stringify(fields))
        var bound = self.bound.clone()
        for entry in members.entries():
            bound.add(entry.key, entry.value.clone())
        return ok(
            Logger(
                self.threshold, self.timestamp, self.max_bytes, bound, self.transport
            )
        )

    # Tests the current filtering threshold; Silent is never enabled as a record level.
    fn enabled(level: LogLevel) Bool:
        let value = level_value(level)
        return value >= self.threshold and value < 70

    # Returns this logger's current threshold, independent of its parent or children.
    fn level() LogLevel:
        return level_at(self.threshold)

    # Changes only this logger's threshold; existing child loggers retain their copied threshold.
    var fn set_level(level: LogLevel) Unit:
        self.threshold = level_value(level)

    # Flushes the logger's transport.
    fn flush() Unit!LogError:
        return self.transport.get().flush()

    # Closes the transport this logger shares with its children, so every one of them reports `Closed`
    # afterwards. A scope that owns the logger calls it on every exit.
    var fn close() Unit:
        self.transport.get().close()

# Creates a logger that owns `transport`. Defaults to `Info`, timestamps enabled, and no record-size limit.
export fn create(
    transport: Transport,
    level: LogLevel?,
    timestamp: Bool?,
    max_bytes: Int?
) Logger!LogError:
    if let max = max_bytes:
        if max < 0: return error(LogError.InvalidInput)

    var threshold = 30
    if let chosen = level:
        threshold = level_value(chosen)
    return ok(
        Logger(
            threshold, timestamp.get(true), max_bytes, Map[String, JsonValue](),
            share(transport)
        )
    )

# Writes log records to an existing byte stream.
export fn stream_transport(output: WriteStream) Transport:
    return StreamTransport(share(StreamState(output, false)))

# Writes log records to the process standard-output stream.
export fn stdout_transport() Transport:
    return stream_transport(stdout())

# Appends log records to a file at `path`.
export fn file_transport(path: String) Transport!LogError:
    match open(path, "a", 420):
        ok(file): return ok(file_stream_transport(file))
        error(cause): return error(LogError.FileSystem(cause))

fn file_stream_transport(file: FileHandle) Transport:
    let stream = StreamTransport(share(StreamState(file.writer(), false)))
    return FileTransport(share(file), stream)

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
