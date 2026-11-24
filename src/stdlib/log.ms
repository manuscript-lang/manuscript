// ms: allow_effect std.clock.read
// ms: allow_effect std.console.write
// ms: allow_effect std.fs.delete
// ms: allow_effect std.fs.read
// ms: allow_effect std.fs.write

import (
	Bytes from "@std/bytes.ms",
	Data from "@std/core.ms",
	JsonValue, parse, stringify from "@std/data/json.ms",
	stdout, stdout_bytes from "@std/io/io.ms",
	FileHandle, OpenMode, OpenOptions, open, remove, rename, stat from "@std/os/fs.ms",
	now from "@std/time.ms",
)

// Severity levels accepted by a logger, ordered from Trace through Fatal.
export enum LogLevel:
	// Most detailed records, encoded with numeric level 10.
	Trace
	// Development diagnostics, encoded with numeric level 20.
	Debug
	// Ordinary operational records, encoded with numeric level 30; the default
	// threshold.
	Info
	// Warning records, encoded with numeric level 40.
	Warn
	// Failure records, encoded with numeric level 50.
	Error
	// Critical records at numeric level 60; logging does not terminate the process.
	Fatal
	// Filtering threshold that disables all records; passing it to `log` returns
	// `EINVAL`.
	Silent

// A destination that accepts encoded log records and can be flushed and closed.
export interface Transport:
	// Accepts one encoded record as text and may return the original I/O cause. An
	// error can follow a partial write to the destination, which is not rolled back.
	// Each logger owns its transport (see `duplicate`), so an implementation needs no
	// locking.
	fn write(move data String) Void!
	// Accepts one encoded record as bytes, with the same rules as `write`.
	fn write_bytes(move data Bytes) Void!
	// Flushes the destination; what that guarantees depends on the destination.
	fn flush() Void!
	// Returns a new transport onto the same destination with its own handle. Each
	// child logger writes through one.
	fn duplicate() move Transport!
	// Releases owned resources. Later writes return `EBADF`.
	move fn close() Void

// The number a level writes into the record's `level` field. Silent is a threshold that
// no record reaches.
fn level_value(level LogLevel) Int:
	match level:
		Trace: return 10
		Debug: return 20
		Info: return 30
		Warn: return 40
		Error: return 50
		Fatal: return 60
		Silent: return 70

fn level_at(value Int) LogLevel:
	if value == 10: return LogLevel.Trace
	if value == 20: return LogLevel.Debug
	if value == 30: return LogLevel.Info
	if value == 40: return LogLevel.Warn
	if value == 50: return LogLevel.Error
	if value == 60: return LogLevel.Fatal

	return LogLevel.Silent

// Milliseconds since the Unix epoch, the unit of the `time` field.
fn now_ms() Int:
	now := now()
	return now.unix_seconds() * 1000 + now.nanoseconds() / 1000000

// Encodes `fields` as JSON text. Anything `stringify` rejects is `EBADMSG`.
fn encode_fields[F Data](fields F) String!:
	text := stringify(fields)
	if text.is_error(): return error(Error("logging: invalid data", kind: "EBADMSG"))

	return ok(text.get())

// The context of a child: the parent's object members with the child's added, or the
// child's text alone when either side is not an object. This runs once per child, never
// per record.
fn merge_context(child String, parent String?) String!:
	base := parent or ""
	if base == "": return ok(child)

	left := parse(base)
	right := parse(child)
	if left.is_error() or right.is_error(): return error(
		Error("logging: invalid data", kind: "EBADMSG")
	)

	members := left.get().as_map()
	added := right.get().as_map()
	if (members == null) or (added == null): return ok(child)

	var merged = (members).clone()
	for entry in (added).entries():
		merged.add(entry.key.clone(), entry.value.clone())

	text := stringify(JsonValue.ObjectValue(merged))
	if text.is_error(): return error(Error("logging: invalid data", kind: "EBADMSG"))

	return ok(text.get())

fn encode_error(cause Error) Error:
	if cause.kind == "EOVERFLOW": return Error(
		"logging: limit exceeded",
		kind: "EOVERFLOW",
	)
	return Error("logging: invalid data", kind: "EBADMSG")

// Appends to an open file. Each logger owns its handle (`duplicate` dups it), so
// loggers on several threads write without sharing state.
type FileTransport:
	file FileHandle
	closed Bool

fn FileTransport.write(move data String) Void!:
	return self.write_bytes(data.to_bytes())

fn FileTransport.write_bytes(move data Bytes) Void!:
	if self.closed: return error(log_closed())
	return self.file.write(data)

fn FileTransport.flush() Void!:
	if self.closed: return error(log_closed())
	return self.file.sync()

fn FileTransport.duplicate() Transport!:
	if self.closed: return error(log_closed())
	return ok(FileTransport(file: self.file.clone()?, closed: false))

fn move FileTransport.close() Void:
	if self.closed: return

	self.closed = true
	void self.file.close()

// Writes to the process standard-output stream. It keeps no handle: every write reaches
// the process-wide buffer.
type StdoutTransport:
	closed Bool

fn StdoutTransport.write(move data String) Void!:
	if self.closed: return error(log_closed())

	var out = stdout()
	return out.write(data)

fn StdoutTransport.write_bytes(move data Bytes) Void!:
	if self.closed: return error(log_closed())

	var out = stdout_bytes()
	return out.write(data)

fn StdoutTransport.flush() Void!:
	if self.closed: return error(log_closed())

	var out = stdout()
	return out.flush()

fn StdoutTransport.duplicate() Transport!:
	if self.closed: return error(log_closed())
	return ok(StdoutTransport(closed: false))

fn move StdoutTransport.close() Void:
	self.closed = true

// A structured logger: level filtering, bound fields, and a pluggable `Transport`. The
// level methods take optional fields of any `Data` type and encode them with
// `stringify`. A child logger owns a duplicate of the transport (its own handle on the
// same destination), so loggers can write from several threads and closing one leaves
// the others open.
export type Logger:
	// Internal state: the lowest level number that is written.
	threshold Int
	// Internal state: whether records carry a `time` field.
	timestamp Bool
	// Internal state: the transport this logger writes to; each child owns a duplicate.
	transport Transport
	// Internal state: the largest record in bytes including the newline; null is
	// unlimited.
	max_bytes Int?
	// Internal state: JSON text of the fields bound by `child`, written as `context`;
	// null if unbound.
	context String?

// Internal: writes one record at a level number. `data` is JSON text attached as
// is.
fn Logger.emit(level Int, message String, data String?) Void!:
	msg := stringify(message)
	if msg.is_error(): return error(encode_error(msg.err()))

	var line = f"\{\"level\":{level},\"msg\":{msg.get()}"
	if self.timestamp: line = f"{line},\"time\":{now_ms()}"

	context := self.context
	if context != null: line = f"{line},\"context\":{context}"

	text := data
	if text != null: line = f"{line},\"data\":{text}"
	line = f"{line}\}\n"

	max := self.max_bytes
	if max != null:
		if line.length() > max: return error(
			Error("logging: limit exceeded", kind: "EOVERFLOW")
		)
	return self.transport.write(line)

/*
Writes a record at the selected level. `fields` is any `Data` value `stringify` accepts.

The value is written as is under the record's `data` key, so a record, map, list, or number
keeps its shape. No fields, or `null`, write the message alone. A value that cannot be encoded,
such as a cyclic one, returns `EBADMSG`; encoding happens only when the level is enabled.
The fields of `child` loggers are written under `context`. `Silent` is a threshold, not a
record level, and returns `EINVAL`.
*/
fn Logger.log[F Data = Void](level LogLevel, message String, fields F? = null) Void!:
	if level == LogLevel.Silent: return error(
		Error("logging: invalid input", kind: "EINVAL")
	)
	if not self.enabled(level): return ok()

	value := fields

	if value != null:
		text := encode_fields(value)?
		return self.emit(level_value(level), message, text)

	return self.emit(level_value(level), message, null)

// Logs at Trace, the most detailed level, when enabled. A filtered call returns ok
// without encoding the fields or touching the transport. Fields are encoded as in
// `log`.
fn Logger.trace[F Data = Void](message String, fields F? = null) Void!:
	return self.log(LogLevel.Trace, message, fields)

// Logs at Debug when enabled, for development diagnostics. Fields are encoded as in
// `log`.
fn Logger.debug[F Data = Void](message String, fields F? = null) Void!:
	return self.log(LogLevel.Debug, message, fields)

// Logs at Info when enabled. Ordinary operational records. Fields are encoded as in
// `log`.
fn Logger.info[F Data = Void](message String, fields F? = null) Void!:
	return self.log(LogLevel.Info, message, fields)

// Logs at Warn when enabled. Returns encoding, size-limit and transport errors
// unchanged. Fields are encoded as in `log`.
fn Logger.warn[F Data = Void](message String, fields F? = null) Void!:
	return self.log(LogLevel.Warn, message, fields)

// Logs at Error when enabled. This records a failure for diagnosis; it does not
// raise a fault. Fields are encoded as in `log`.
fn Logger.error[F Data = Void](message String, fields F? = null) Void!:
	return self.log(LogLevel.Error, message, fields)

// Logs at Fatal when enabled. Logging does not stop the process; the caller must
// do that. Fields are encoded as in `log`.
fn Logger.fatal[F Data = Void](message String, fields F? = null) Void!:
	return self.log(LogLevel.Fatal, message, fields)

/*
Returns a logger that writes `fields` under `context` in each record. A child of a child merges
object members, and the newer value wins on a clash; if either side is not an object, the newer
value replaces the older one. A value that cannot be encoded returns `EBADMSG`.
*/
fn Logger.child[F Data](fields F) Logger!:
	text := encode_fields(fields)?
	context := merge_context(text, self.context)?
	own := self.transport.duplicate()?
	return ok(Logger(self.threshold, self.timestamp, own, self.max_bytes, context))

// Tests whether records at `level` pass the threshold; `Silent` is never enabled.
fn Logger.enabled(level LogLevel) Bool:
	value := level_value(level)
	return value >= self.threshold and value < 70

// Returns this logger's current threshold, independent of its parent or children.
fn Logger.level() LogLevel:
	return level_at(self.threshold)

// Changes only this logger's threshold; existing child loggers keep the threshold
// they copied.
fn var Logger.set_level(level LogLevel) Void:
	self.threshold = level_value(level)

// Flushes the logger's transport.
fn Logger.flush() Void!:
	return self.transport.flush()

// Closes this logger's transport and consumes the logger. A scope that owns a
// logger should close it on every exit. Children and the parent are not affected.
fn move Logger.close() Void!:
	self.transport.close()

// Settings for `create`: the minimum level (default Info), whether records carry a
// timestamp (default true), and an optional per-record byte limit.
export type LoggerOptions:
	// Records below this level are dropped.
	level LogLevel = LogLevel.Info
	// True adds a timestamp to every record.
	timestamp Bool = true
	// Maximum encoded bytes of one record; null adds no limit.
	max_bytes Int? = null

// Creates a logger that owns `transport`, with the level, timestamp and record-size
// settings in `options`.
export fn create(
	move transport Transport,
	options LoggerOptions = LoggerOptions(),
) Logger!:
	max := options.max_bytes
	if max != null:
		if max < 0: return error(Error("logging: invalid input", kind: "EINVAL"))
	return ok(
		Logger(
			level_value(options.level),
			options.timestamp,
			transport,
			options.max_bytes,
			null,
		)
	)

// Writes log records to the process standard-output stream.
// ms: effect std.console.write
export fn stdout_transport() Transport:
	return StdoutTransport(closed: false)

// Appends log records to an open file. The transport owns `file`; closing the transport
// closes it.
export fn handle_transport(move file FileHandle) Transport:
	return FileTransport(file: file, closed: false)

// Appends log records to a file at `path`.
// ms: effect std.fs.write
export fn file_transport(path String) Transport!:
	file := open(path, OpenMode.Append, OpenOptions(permissions: 420))?
	return ok(handle_transport(file))

// Appends to a file like `file_transport`, but moves it aside when a record would
// take it past a size limit. It opens the file for each record, so loggers see each
// other's rotations; two loggers rotating at the same instant can lose records.
type RotatingTransport:
	path String
	max_bytes Int
	keep Int
	closed Bool

fn RotatingTransport.write(move data String) Void!:
	return self.write_bytes(data.to_bytes())

fn RotatingTransport.write_bytes(move data Bytes) Void!:
	if self.closed: return error(log_closed())

	var size = 0
	if existing := stat(self.path): size = existing.size
	if size > 0 and size + data.length() > self.max_bytes:
		rotate(self.path, self.keep)

	var file = open(self.path, OpenMode.Append, OpenOptions(permissions: 420))?
	written := file.write(data)
	void file.close()
	return written

fn RotatingTransport.flush() Void!:
	if self.closed: return error(log_closed())

fn RotatingTransport.duplicate() Transport!:
	if self.closed: return error(log_closed())
	return ok(
		RotatingTransport(
			path: self.path.clone(),
			max_bytes: self.max_bytes,
			keep: self.keep,
			closed: false,
		)
	)

fn move RotatingTransport.close() Void:
	self.closed = true

// Shifts `path.1` to `path.2` and so on (dropping the oldest), then moves `path` to
// `path.1`.
fn rotate(path String, keep Int) Void:
	_oldest := remove(f"{path}.{keep}", recursive: false)
	var index = keep - 1

	while index >= 1:
		_shifted := rename(f"{path}.{index}", f"{path}.{index + 1}")
		index -= 1

	if keep >= 1:
		_aside := rename(path, f"{path}.1")
	else:
		_discarded := remove(path, recursive: false)

/*
Appends log records to the file at `path` and rotates it by size.
When a record would take the file past `max_bytes`, the file is renamed to `path.1`, an older `path.1` to `path.2`, and so on up to `path.<keep>`; the oldest is deleted.
`max_bytes` must be positive, and a single record larger than it is still written whole, to a fresh file.
`keep` is the number of rotated files to retain, zero or more; zero discards the old contents.
A non-positive `max_bytes` or a negative `keep` returns `EINVAL`.
An existing file is appended to, and its current size counts toward `max_bytes`.
Example: `create(rotating_file_transport("app.log", max_bytes: 1048576, keep: 5))`.
*/
// ms: effect std.fs.write
export fn rotating_file_transport(path String, max_bytes Int, keep Int) Transport!:
	if max_bytes <= 0 or keep < 0: return error(
		Error("logging: invalid input", kind: "EINVAL")
	)

	var probe = open(path, OpenMode.Append, OpenOptions(permissions: 420))?
	void probe.close()
	return ok(
		RotatingTransport(
			path: path.clone(),
			max_bytes: max_bytes,
			keep: keep,
			closed: false,
		)
	)

fn log_closed() Error:
	return Error("logging: resource is closed", kind: "EBADF")
