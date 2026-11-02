import Data from "@std/core.ms"
import WriteStream from "@std/io/io.ms"
import Bytes from "@std/bytes.ms"
import Shared, share from "@std/concurrency/shared.ms"
import lock from "@std/concurrency/sync.ms"
import FileHandle, open from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"
import JsonValue, parse, stringify from "@std/data/json.ms"
import now from "@std/os/time.ms"

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
    fn write(data: String) Unit!
    # Accepts encoded record bytes with the same rules as write.
    fn write_bytes(data: Bytes) Unit!
    # Delegates flush to the destination; persistence and buffering depend on that destination.
    fn flush() Unit!
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

# Encodes `fields` as JSON text. Anything `stringify` rejects is `InvalidData`.
fn encode_fields[F: Data](fields: F) String!:
    let text = stringify(fields)
    if text.is_error(): return error(Error("logging: invalid data", kind: InvalidData))

    return ok(text.get())

# The context of a child: the parent's object members with the child's added, or the child's text
# alone when either side is not an object. This runs once per child, never per record.
fn merge_context(parent: String?, child: String) String!:
    let base = parent.get("")
    if base == "": return ok(child)

    let left = parse(base)
    let right = parse(child)
    if left.is_error() or right.is_error(): return error(
        Error("logging: invalid data", kind: InvalidData)
    )

    let members = left.get().as_map()
    let added = right.get().as_map()
    if members.is_none() or added.is_none(): return ok(child)

    var merged = members.get(Map[String, JsonValue]()).clone()
    for entry in added.get(Map[String, JsonValue]()).entries():
        merged.add(entry.key, entry.value.clone())

    let text = stringify(JsonValue.ObjectValue(merged))
    if text.is_error(): return error(Error("logging: invalid data", kind: InvalidData))

    return ok(text.get())

fn encode_error(cause: Error) Error:
    if cause.kind == ErrorCategory.LimitExceeded: return Error(
        "logging: limit exceeded", kind: LimitExceeded
    )

    return Error("logging: invalid data", kind: InvalidData)

# The open stream of a stream transport and whether the transport was closed.
type StreamState:
    stream: WriteStream
    closed: Bool

# Writes to a byte stream. Child loggers share one transport, so the state is guarded here: the
# logger itself never locks. Closing a transport over a caller's stream leaves the stream open.
type StreamTransport:
    state: Shared[StreamState]

impl Transport for StreamTransport:
    fn write(data: String) Unit!:
        var guard = lock(self.state)
        if guard.value.closed: return error(
            Error("logging: resource is closed", kind: Closed)
        )

        match guard.value.stream.write(data):
            ok(_): return ok(unit)
            error(cause): return error(cause)

    fn write_bytes(data: Bytes) Unit!:
        var guard = lock(self.state)
        if guard.value.closed: return error(
            Error("logging: resource is closed", kind: Closed)
        )

        match guard.value.stream.write_bytes(data):
            ok(_): return ok(unit)
            error(cause): return error(cause)

    fn flush() Unit!:
        var guard = lock(self.state)
        if guard.value.closed: return error(
            Error("logging: resource is closed", kind: Closed)
        )

        match guard.value.stream.flush():
            ok(_): return ok(unit)
            error(cause): return error(cause)

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
    fn write(data: String) Unit!:
        return self.inner.write(data)

    fn write_bytes(data: Bytes) Unit!:
        return self.inner.write_bytes(data)

    fn flush() Unit!:
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
    # Internal state: JSON text of the fields bound by `child`, written as `context`; none if unbound.
    context: String?
    # Internal state: the transport this logger and its children write to.
    transport: Shared[Transport]

impl Logger:
    # Internal: writes one record at a level number. `data` is JSON text attached as is.
    fn emit(level: Int, message: String, data: String?) Unit!:
        let msg = stringify(JsonValue.StringValue(message))
        if msg.is_error(): return error(encode_error(msg.err()))

        var line = "\{\"level\":{level},\"msg\":{msg.get()}"
        if self.timestamp: line = "{line},\"time\":{now_ms()}"
        if let context = self.context: line = "{line},\"context\":{context}"
        if let text = data: line = "{line},\"data\":{text}"
        line = "{line}\}\n"
        if let max = self.max_bytes:
            if line.to_bytes().length() > max: return error(
                Error("logging: limit exceeded", kind: LimitExceeded)
            )
        return self.transport.get().write(line)

    # Writes a record at the selected level. `fields` is any `Data` value `stringify` accepts.
    #
    # The value is written as is under the record's `data` key, so a record, map, list, or number
    # keeps its shape. No fields, or `none`, write the message alone. A value that cannot be encoded,
    # such as a cyclic one, returns `InvalidData`; encoding happens only when the level is enabled.
    # The fields of `child` loggers are written under `context`. `Silent` is a threshold, not a
    # record level, and returns `InvalidInput`.
    fn log[F: Data = Unit](level: LogLevel, message: String, fields: F? = none) Unit!:
        if level == LogLevel.Silent: return error(
            Error("logging: invalid input", kind: InvalidInput)
        )
        if not self.enabled(level): return ok(unit)

        if let value = fields:
            let text = try encode_fields(value)
            return self.emit(level_value(level), message, text)

        return self.emit(level_value(level), message, none)

    # Logs at Trace when enabled. Most detailed records; a filtered call returns ok without encoding or transport access. Fields are encoded as in `log`.
    fn trace[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Trace, message, fields)

    # Logs at Debug when enabled. Development diagnostics, including the logger's `context`. Fields are encoded as in `log`.
    fn debug[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Debug, message, fields)

    # Logs at Info when enabled. Ordinary operational records. Fields are encoded as in `log`.
    fn info[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Info, message, fields)

    # Logs at Warn when enabled. Warning records, returning encoding, size-budget, or transport errors unchanged. Fields are encoded as in `log`.
    fn warn[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Warn, message, fields)

    # Logs at Error when enabled. Failure records: an expected diagnostic rather than a fault. Fields are encoded as in `log`.
    fn error[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Error, message, fields)

    # Logs at Fatal when enabled. Critical records; the caller remains responsible for process termination. Fields are encoded as in `log`.
    fn fatal[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Fatal, message, fields)

    # Returns a logger that writes `fields` under `context` in each record. A child of a child merges
    # object members, the newer value winning; any other combination keeps the newer value. A value
    # that cannot be encoded returns `InvalidData`.
    fn child[F: Data](fields: F) Logger!:
        let text = try encode_fields(fields)
        let context = try merge_context(self.context, text)
        return ok(
            Logger(
                self.threshold, self.timestamp, self.max_bytes, context, self.transport
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
    fn flush() Unit!:
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
) Logger!:
    if let max = max_bytes:
        if max < 0: return error(Error("logging: invalid input", kind: InvalidInput))

    var threshold = 30
    if let chosen = level:
        threshold = level_value(chosen)
    return ok(Logger(threshold, timestamp.get(true), max_bytes, none, share(transport)))

# Writes log records to an existing byte stream.
export fn stream_transport(output: WriteStream) Transport:
    return StreamTransport(share(StreamState(output, false)))

# Writes log records to the process standard-output stream.
export fn stdout_transport() Transport:
    return stream_transport(stdout())

# Appends log records to a file at `path`.
export fn file_transport(path: String) Transport!:
    match open(path, "a", 420):
        ok(file): return ok(file_stream_transport(file))
        error(cause): return error(cause)

fn file_stream_transport(file: FileHandle) Transport:
    let stream = StreamTransport(share(StreamState(file.writer(), false)))
    return FileTransport(share(file), stream)
