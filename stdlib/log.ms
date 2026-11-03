import Closeable, Data from "@std/core.ms"
import Bytes from "@std/bytes.ms"
import FileHandle, open, remove, rename, stat from "@std/os/fs.ms"
import stdout from "@std/io/io.ms"
import JsonValue, parse, stringify from "@std/data/json.ms"
import now from "@std/os/time.ms"

// Severity levels accepted by a logger, ordered from Trace through Fatal.
export type LogLevel:
    // Most detailed records, encoded with numeric level 10.
    case Trace
    // Development diagnostics, encoded with numeric level 20.
    case Debug
    // Ordinary operational records, encoded with numeric level 30; the default threshold.
    case Info
    // Warning records, encoded with numeric level 40.
    case Warn
    // Failure records, encoded with numeric level 50.
    case Error
    // Critical records at numeric level 60; logging does not terminate the process.
    case Fatal
    // Filtering threshold that disables records; passing it to log returns InvalidInput.
    case Silent

// A destination that accepts encoded log records and can be flushed and closed.
export interface Transport:
    // Accepts encoded record bytes and may return the original I/O cause. Errors can follow a partial
    // external write, without rollback. Loggers on several threads each own a
    // transport (see `duplicate`), so an implementation needs no locking.
    fn write(data: String) Unit!
    // Accepts encoded record bytes with the same rules as write.
    fn write_bytes(data: Bytes) Unit!
    // Delegates flush to the destination; persistence and buffering depend on that destination.
    fn flush() Unit!
    // A new transport onto the same destination with its own handle; child loggers write through one each.
    fn duplicate() Transport!
    // Releases owned resources. Later writes return `Closed`.
    var fn close() Unit

// The number a level writes into the record's `level` field. Silent is a threshold that no record reaches.
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

// Milliseconds since the Unix epoch, the unit of the `time` field.
fn now_ms() Int:
    let now = now()
    return now.unix_seconds() * 1000 + now.nanoseconds() / 1000000

// Encodes `fields` as JSON text. Anything `stringify` rejects is `InvalidData`.
fn encode_fields[F: Data](fields: F) String!:
    let text = stringify(fields)
    if text.is_error(): return error(
        Error("logging: invalid data", kind: ErrorCategory.InvalidData)
    )

    return ok(text.get())

// The context of a child: the parent's object members with the child's added, or the child's text
// alone when either side is not an object. This runs once per child, never per record.
fn merge_context(parent: String?, child: String) String!:
    let base = parent.get("")
    if base == "": return ok(child)

    let left = parse(base)
    let right = parse(child)
    if left.is_error() or right.is_error(): return error(
        Error("logging: invalid data", kind: ErrorCategory.InvalidData)
    )

    let members = left.get().as_map()
    let added = right.get().as_map()
    if members.is_none() or added.is_none(): return ok(child)

    var merged = members.get(Map[String, JsonValue]()).clone()
    for entry in added.get(Map[String, JsonValue]()).entries():
        merged.add(entry.key, entry.value.clone())

    let text = stringify(JsonValue.ObjectValue(merged))
    if text.is_error(): return error(
        Error("logging: invalid data", kind: ErrorCategory.InvalidData)
    )

    return ok(text.get())

fn encode_error(cause: Error) Error:
    if cause.kind == ErrorCategory.LimitExceeded: return Error(
        "logging: limit exceeded", kind: ErrorCategory.LimitExceeded
    )

    return Error("logging: invalid data", kind: ErrorCategory.InvalidData)

// Appends to an open file. Each logger owns its handle (`duplicate` dups it), so loggers on several threads write without sharing state.
type FileTransport:
    file: FileHandle
    closed: Bool

impl Transport for FileTransport:
    fn write(data: String) Unit!:
        return self.write_bytes(data.to_bytes())

    fn write_bytes(data: Bytes) Unit!:
        if self.closed: return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        return self.file.write_bytes(data)

    fn flush() Unit!:
        if self.closed: return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        return self.file.sync()

    fn duplicate() Transport!:
        if self.closed: return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        return ok(FileTransport(file: try self.file.clone(), closed: false))

    var fn close() Unit:
        if self.closed: return

        self.closed = true
        self.file.close().get(none)

// Writes to the process standard-output stream. It keeps no handle: every write reaches the process-wide buffer.
type StdoutTransport:
    closed: Bool

impl Transport for StdoutTransport:
    fn write(data: String) Unit!:
        if self.closed: return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        var out = stdout()
        return out.write(data)

    fn write_bytes(data: Bytes) Unit!:
        if self.closed: return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        var out = stdout()
        return out.write_bytes(data)

    fn flush() Unit!:
        if self.closed: return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        var out = stdout()
        return out.flush()

    fn duplicate() Transport!:
        if self.closed: return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        return ok(StdoutTransport(closed: false))

    var fn close() Unit:
        self.closed = true

// A structured logger: level filtering, bound fields, and a pluggable `Transport`. The level methods
// take optional fields of any `Data` type and encode them with `stringify`. A child logger owns a
// duplicate of the transport (its own handle on the same destination), so loggers can write from several threads and
// closing one leaves the others open.
export type Logger:
    // Internal state: the lowest level number that is written.
    threshold: Int
    // Internal state: whether records carry a `time` field.
    timestamp: Bool
    // Internal state: the largest record in bytes including the newline; none is unlimited.
    max_bytes: Int?
    // Internal state: JSON text of the fields bound by `child`, written as `context`; none if unbound.
    context: String?
    // Internal state: the transport this logger writes to; each child owns a duplicate.
    transport: Transport

impl Logger:
    // Internal: writes one record at a level number. `data` is JSON text attached as is.
    fn emit(level: Int, message: String, data: String?) Unit!:
        let msg = stringify(JsonValue.StringValue(message))
        if msg.is_error(): return error(encode_error(msg.err()))

        var line = "\{\"level\":{level},\"msg\":{msg.get()}"
        if self.timestamp: line = "{line},\"time\":{now_ms()}"
        if let context = self.context: line = "{line},\"context\":{context}"
        if let text = data: line = "{line},\"data\":{text}"
        line = "{line}\}\n"
        if let max = self.max_bytes:
            if line.byte_length() > max: return error(
                Error(
                    "logging: limit exceeded", kind: ErrorCategory.LimitExceeded
                )
            )
        return self.transport.write(line)

    /*
    Writes a record at the selected level. `fields` is any `Data` value `stringify` accepts.

    The value is written as is under the record's `data` key, so a record, map, list, or number
    keeps its shape. No fields, or `none`, write the message alone. A value that cannot be encoded,
    such as a cyclic one, returns `InvalidData`; encoding happens only when the level is enabled.
    The fields of `child` loggers are written under `context`. `Silent` is a threshold, not a
    record level, and returns `InvalidInput`.
    */
    fn log[F: Data = Unit](level: LogLevel, message: String, fields: F? = none) Unit!:
        if level == LogLevel.Silent: return error(
            Error(
                "logging: invalid input", kind: ErrorCategory.InvalidInput
            )
        )
        if not self.enabled(level): return ok(unit)

        if let value = fields:
            let text = try encode_fields(value)
            return self.emit(level_value(level), message, text)

        return self.emit(level_value(level), message, none)

    // Logs at Trace when enabled. Most detailed records; a filtered call returns ok without encoding or transport access. Fields are encoded as in `log`.
    fn trace[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Trace, message, fields)

    // Logs at Debug when enabled. Development diagnostics, including the logger's `context`. Fields are encoded as in `log`.
    fn debug[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Debug, message, fields)

    // Logs at Info when enabled. Ordinary operational records. Fields are encoded as in `log`.
    fn info[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Info, message, fields)

    // Logs at Warn when enabled. Warning records, returning encoding, size-budget, or transport errors unchanged. Fields are encoded as in `log`.
    fn warn[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Warn, message, fields)

    // Logs at Error when enabled. Failure records: an expected diagnostic rather than a fault. Fields are encoded as in `log`.
    fn error[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Error, message, fields)

    // Logs at Fatal when enabled. Critical records; the caller remains responsible for process termination. Fields are encoded as in `log`.
    fn fatal[F: Data = Unit](message: String, fields: F? = none) Unit!:
        return self.log(LogLevel.Fatal, message, fields)

    /*
    Returns a logger that writes `fields` under `context` in each record. A child of a child merges
    object members, the newer value winning; any other combination keeps the newer value. A value
    that cannot be encoded returns `InvalidData`.
    */
    fn child[F: Data](fields: F) Logger!:
        let text = try encode_fields(fields)
        let context = try merge_context(self.context, text)
        let own = try self.transport.duplicate()
        return ok(Logger(self.threshold, self.timestamp, self.max_bytes, context, own))

    // Tests the current filtering threshold; Silent is never enabled as a record level.
    fn enabled(level: LogLevel) Bool:
        let value = level_value(level)
        return value >= self.threshold and value < 70

    // Returns this logger's current threshold, independent of its parent or children.
    fn level() LogLevel:
        return level_at(self.threshold)

    // Changes only this logger's threshold; existing child loggers retain their copied threshold.
    var fn set_level(level: LogLevel) Unit:
        self.threshold = level_value(level)

    // Flushes the logger's transport.
    fn flush() Unit!:
        return self.transport.flush()

    // Closes this logger's transport; later records return `Closed`. Children and the parent are not affected.
    var fn close() Unit:
        self.transport.close()

// Creates a logger that owns `transport`. Defaults to `Info`, timestamps enabled, and no record-size limit.
export fn create(
    transport: Transport,
    level: LogLevel?,
    timestamp: Bool?,
    max_bytes: Int?
) Logger!:
    if let max = max_bytes:
        if max < 0: return error(
            Error(
                "logging: invalid input", kind: ErrorCategory.InvalidInput
            )
        )

    var threshold = 30
    if let chosen = level:
        threshold = level_value(chosen)
    return ok(Logger(threshold, timestamp.get(true), max_bytes, none, transport))

// Writes log records to the process standard-output stream.
export fn stdout_transport() Transport:
    return StdoutTransport(closed: false)

// Appends log records to an open file. The transport owns `file`; closing the transport closes it.
export fn handle_transport(file: FileHandle) Transport:
    return FileTransport(file: file, closed: false)

// Appends log records to a file at `path`.
export fn file_transport(path: String) Transport!:
    match open(path, "a", 420):
        ok(file): return ok(handle_transport(file))
        error(cause): return error(cause)

// Appends to a file and moves it aside once it would exceed a size, as `file_transport` does otherwise. It opens the file for each record, so a rotation by one logger is seen by the others; two loggers rotating at the same instant can lose records.
type RotatingTransport:
    path: String
    max_bytes: Int
    keep: Int
    closed: Bool

// Shifts `path.1` to `path.2` and so on (dropping the oldest), then moves `path` to `path.1`.
fn rotate(path: String, keep: Int) Unit:
    let _oldest = remove("{path}.{keep}", false)
    var index = keep - 1

    while index >= 1:
        let _shifted = rename("{path}.{index}", "{path}.{index + 1}")
        index -= 1

    if keep >= 1:
        let _aside = rename(path, "{path}.1")
    else:
        let _discarded = remove(path, false)

impl Transport for RotatingTransport:
    fn write(data: String) Unit!:
        return self.write_bytes(data.to_bytes())

    fn write_bytes(data: Bytes) Unit!:
        if self.closed: return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        var size = 0
        if let existing = stat(self.path, true): size = existing.size
        if size > 0 and size + data.length() > self.max_bytes:
            rotate(self.path, self.keep)

        var file = try open(self.path, "a", 420)
        let written = file.write_bytes(data)
        file.close().get(none)
        return written

    fn flush() Unit!:
        if self.closed: return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        return ok(unit)

    fn duplicate() Transport!:
        if self.closed: return error(
            Error("logging: resource is closed", kind: ErrorCategory.Closed)
        )

        return ok(
            RotatingTransport(
                path: self.path.clone(), max_bytes: self.max_bytes, keep: self.keep,
                closed: false
            )
        )

    var fn close() Unit:
        self.closed = true

/*
Appends log records to the file at `path` and rotates it by size.
When a record would take the file past `max_bytes` (a positive size; a single larger record is still written whole, to a fresh file), the file is renamed to `path.1`, an older `path.1` to `path.2`, and so on up to `path.<keep>`; the oldest is deleted. `keep` is the number of rotated files to retain, zero or more, and zero discards the old contents. A non-positive `max_bytes` or a negative `keep` returns `InvalidInput`. An existing file keeps being appended to, counting its current size.
Example: `create(rotating_file_transport("app.log", max_bytes: 1048576, keep: 5), none, none, none)`.
*/
export fn rotating_file_transport(path: String, max_bytes: Int, keep: Int) Transport!:
    if max_bytes <= 0 or keep < 0: return error(
        Error("logging: invalid input", kind: ErrorCategory.InvalidInput)
    )

    match open(path, "a", 420):
        ok(file):
            var probe = file
            probe.close().get(none)
            return ok(
                RotatingTransport(
                    path: path.clone(), max_bytes: max_bytes, keep: keep, closed: false
                )
            )
        error(cause): return error(cause)
