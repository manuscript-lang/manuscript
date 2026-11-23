import Bytes from "@std/bytes.ms"

// An expected failure as a plain value: a message, a short code callers can branch on,
// and string details. Build one like any record:
// `Error("no such file", kind: "ENOENT", details: {"path": path})`. `T!` is
// `Result[T, Error]`.
export type Error:
	// Human-readable description of the failure.
	message: String
	// A short code for what went wrong, or `none` when no code fits. The kind itself
	// never allocates when it is a literal or at most 15 bytes. The standard library
	// reports POSIX errno names (`EAUTH` is Manuscript's own), so
	// `error.kind == "ENOENT"` means the same on every platform:
	//
	// - `EINVAL`: caller input is invalid
	// - `EBADMSG`: input data is malformed
	// - `EOVERFLOW`: a limit was exceeded
	// - `ERANGE`: a value or index is out of range
	// - `ENOENT`: not found
	// - `EEXIST`: already exists
	// - `ENOTEMPTY`: directory not empty
	// - `EACCES`: permission denied
	// - `ENOTSUP`: unsupported
	// - `ENOTTY`: not a terminal
	// - `EBADF`: resource closed
	// - `EIO`: a task, process or peer ended abnormally
	// - `EAGAIN`: service unavailable
	// - `EBUSY`: resource busy
	// - `ETIMEDOUT`: a deadline expired
	// - `ECANCELED`: cancelled
	// - `EAUTH`: authentication failed
	//
	// Your own code uses its own prefix, such as `"EQUOTA"`.
	kind: String? = none
	// Extra facts about the failure, such as the path or operation, keyed by name.
	details: Map[String, String] = Map[String, String]()

// The runtime reports a failed native as a status number; lowering builds the `Error`
// from these rows (`// ms: status <number> <kind> <words>`, built by
// crates/ms-lower/build.rs). The message is `<domain>: <words>`, and `-` words mean the
// native's own text is the whole message. A module that words a status differently
// declares `// ms: words <number> <words>` at the top of its file, covering the externs
// that file declares.
// ms: status 1 EINVAL invalid input
// ms: status 2 ERANGE value out of range
// ms: status 3 EOVERFLOW limit exceeded
// ms: status 4 EBADMSG invalid data
// ms: status 5 ENOENT not found
// ms: status 6 EEXIST already exists
// ms: status 7 ENOTEMPTY directory not empty
// ms: status 8 EACCES permission denied
// ms: status 9 ENOTSUP operation not supported
// ms: status 10 EBADF resource is closed
// ms: status 11 EIO -
// ms: status 12 EAGAIN service unavailable
// ms: status 13 ETIMEDOUT operation timed out
// ms: status 14 EOVERFLOW output limit exceeded
// ms: status 15 ENOTTY not a terminal
// ms: status 17 EBUSY terminal is busy
// ms: status 18 EAUTH authentication failed

// The kind of the `Error` a runtime status stands for (see the rows above).
fn status_kind(status: Int) String:
	if status == 1: return "EINVAL"
	if status == 2: return "ERANGE"
	if status == 3: return "EOVERFLOW"
	if status == 4: return "EBADMSG"
	if status == 5: return "ENOENT"
	if status == 6: return "EEXIST"
	if status == 7: return "ENOTEMPTY"
	if status == 8: return "EACCES"
	if status == 9: return "ENOTSUP"
	if status == 10: return "EBADF"
	if status == 11: return "EIO"
	if status == 12: return "EAGAIN"
	if status == 13: return "ETIMEDOUT"
	if status == 14: return "EOVERFLOW"
	if status == 15: return "ENOTTY"
	if status == 17: return "EBUSY"
	return "EAUTH"

// The words of a status; `-` means the native's own text is the whole message.
fn status_words(status: Int) String:
	if status == 1: return "invalid input"
	if status == 2: return "value out of range"
	if status == 3: return "limit exceeded"
	if status == 4: return "invalid data"
	if status == 5: return "not found"
	if status == 6: return "already exists"
	if status == 7: return "directory not empty"
	if status == 8: return "permission denied"
	if status == 9: return "operation not supported"
	if status == 10: return "resource is closed"
	if status == 11: return "-"
	if status == 12: return "service unavailable"
	if status == 13: return "operation timed out"
	if status == 14: return "output limit exceeded"
	if status == 15: return "not a terminal"
	if status == 17: return "terminal is busy"
	return "authentication failed"

// The `Error` of a failed runtime native: `status` is the native's status number, `domain` names what it works
// on, and `said` is the text the native explained itself in, or empty. `overrides` holds the
// `// ms: words NUMBER TEXT` lines of the file that declares the native, one per line, and takes the place of
// the status's usual words. Lowering calls this for every `extern fn` that returns `T!`.
fn msstd_status_error(status: UInt8, domain: String, move said: String, overrides: String) Error:
	number := status.to_int()
	kind := status_kind(number)
	words := override_words(overrides, number).get_or(status_words(number))
	return status_error_text(words, kind, domain, said)

// The words `overrides` gives `number`, if any.
fn override_words(overrides: String, number: Int) String?:
	for line in overrides.split("\n"):
		if words := line.cut_prefix(f"{number} "): return words
	return none

fn status_error_text(words: String, move kind: String, domain: String, move said: String) Error:
	if words == "-":
		if said.length() > 0: return Error(said, kind: kind)
		return Error(f"{domain}: failed", kind: kind)
	if said.starts_with(f"{domain}: "): return Error(said, kind: kind)
	if said.length() > 0: return Error(f"{domain}: {words}: {said}", kind: kind)
	return Error(f"{domain}: {words}", kind: kind)

// Raises a programming fault with the supplied message and stops the current operation.
export fn panic(message: String) Never: ...

// The process-wide output buffer; standard output is flushed at exit
// (crates/ms-rt/src/io.rs).
extern fn msrt_io_write_stdout(text: String) Void

/*
Writes `value` as text, followed by `end` (a newline unless given), to standard output. `print(chunk, end: "")` streams text without a newline.
A type that declares its own `to_string()` prints that text, also when nested in a list or map; other records print structurally.
`print` returns `Void`. Output to a terminal is flushed at each newline. Output to a pipe or file is flushed when the program blocks or exits, so a line printed before a wait is visible while it waits.
Use `stdout()` from `@std/io/io.ms` to write text with no appended newline, or `stdout_bytes()` for bytes.

<!-- manuscript-example: {"mode":"fragment","given":["total: Int","order: String"]} -->
```manuscript
print(f"total: {total}")
print(order)
```
*/
// ms: effect std.console.write
export fn print[T](value: T, end: String = "\n") Void:
	msrt_io_write_stdout(value.to_string() + end)

/*
Data that a write accepts as either text or raw bytes. `String` and `Bytes` both implement it, so
`write_file(path, "text")` and `write_file(path, bytes)` call the same function.
Text is written as its UTF-8 encoding.
*/
export interface Writable:
	// The bytes to write, as a new value the writer may keep.
	fn as_bytes() move Bytes

/*
A resource that can be closed. A binding that holds one is closed when its scope ends, on every exit.

The implicit close behaves like `value.close()?`: a failed close becomes the function's error, after the
other bindings of the scopes it leaves have closed. A failed close is a fault where the function cannot
return an `Error`, or where the resource sits inside a holder (a record, list or temporary).
If the scope is already returning an error, that error is kept and the close error is dropped.
Call `close()` yourself to handle the failure; the binding is then consumed.
*/
export interface Closeable:
	/*
Releases the resource. The compiler calls this on every scope exit, including
returns, expected errors, faults and cancellation. A type whose release cannot fail
returns `ok()`.
    */
	move fn close() Void!

/*
A source of items that `for` walks: each `next` returns the following item, or `none` once exhausted.
`for item in source:` calls `next` until `none`. A variable or field path advances in place and
keeps its final state, while any other expression is held by the loop alone.
`next` should keep returning `none` after the end.
The item is a borrow: it stays valid, and the iterator stays unchanged, until the loop body ends. Clone it to keep it.
*/
export interface Iterator[T]:
	// Returns the next item, or none when no items remain. The item borrows from the
	// iterator (an iterator over a container borrows from the container instead).
	var fn next() T?

// Represents a value that may be absent: a `T` or `none`; a plain `T` converts where a
// `T?` is expected.
export enum Optional[T]:
	// A present payload, retained by reference when T is mutable.
	some(
		// The contained value; unwrap and matching return this original payload.
		value: T
	)
	// An absent value with no payload; no T needs to be constructed.
	none

// Reports whether a value is present.
fn Optional[T].is_some() Bool:
	match self:
		none: return false
		value: return true

// Reports whether this value is absent.
fn Optional[T].is_none() Bool:
	match self:
		none: return true
		value: return false

// Returns the payload; `none` raises a fault, so use it only when absence is a bug.
// Prefer `if value := optional:` or `get_or(default)`.
fn Optional[T].get() T:
	match self:
		value: return value
		none: panic("called Optional.get() on none; check is_some first, or pass a default: get(default: ...)")

// Returns the payload, or `default` when this is `none`. The default is always
// evaluated; use `get_or_else` when it costs work.
fn move Optional[T].get_or(move default: T?) T:
	if value := self: return value
	if fallback := default: return fallback
	panic("called Optional.get_or with a none default")

// Transforms a present payload with `transform`; `none` stays `none`.
fn move Optional[T].map[U](transform: fn(move T) U) U?:
	match self:
		value: return transform(value)
		none: return none

// Calls `transform` only when a value is present and returns the Optional it
// produces; `none` stays `none`.
fn move Optional[T].and_then[U](transform: fn(move T) U?) U?:
	match self:
		value: return transform(value)
		none: return none

// Returns the payload; only when this is `none`, calls `create` once and returns its
// value.
fn Optional[T].get_or_else(create: fn() T) T:
	if self.is_none(): return create()
	return self.get()

// Returns this value when present; otherwise calls `create` once and returns the
// Optional it produces.
fn move Optional[T].or_else(create: fn() T?) T?:
	match self:
		value: return value
		none: return create()

// Returns `ok` with the payload, or `error` with `cause`, which is built before the
// call whether or not it is used.
fn move Optional[T].ok_or[E](move cause: E) move T!E:
	if value := self: return ok(value)
	return error(cause)

// Returns `ok` with the payload; for `none`, calls `create` once and returns its
// error.
fn Optional[T].ok_or_else[E](create: fn() E) T!E:
	if self.is_none(): return error(create())
	return ok(self.get())

// Holds either a successful value (`ok`) or an expected failure (`error`).
export enum Result[T, E]:
	// A successful result, retaining its payload without a deep copy.
	ok(
		// The successful value returned by unwrap, matching, or propagation.
		value: T
	)
	// An expected failure value; it is distinct from faults and cancellation.
	error(
		// The original domain error, retained through compatible Result propagation.
		cause: E
	)

// Reports whether this result contains a successful value.
fn Result[T, E].is_ok() Bool:
	match self:
		ok(_): return true
		error(_): return false

// Reports whether this result contains an expected error.
fn Result[T, E].is_error() Bool:
	match self:
		ok(_): return false
		error(_): return true

// Returns the successful payload; an error raises a fault, so use it only when
// failure is a bug. Prefer `?`, `if value := result:` or `get_or(default)`.
fn Result[T, E].get() T:
	match self:
		ok(value): return value
		error(_): panic("called Result.get() on error; check is_ok first, or pass a default: get(default: ...)")

// Returns the successful payload, or `default` when this is an error. The default is
// always evaluated; use `get_or_else` when it costs work.
fn move Result[T, E].get_or(move default: T?) T:
	if value := self: return value
	if fallback := default: return fallback
	panic("called Result.get_or with a none default")

// Returns the error payload; check `is_error()` first, because a successful result
// raises a fault.
fn Result[T, E].err() E:
	match self:
		ok(_): panic("called Result.err() on ok; check is_error first")
		error(cause): return cause

// Returns the successful payload; for an error, calls `create` once with that error
// and returns its value.
fn move Result[T, E].get_or_else(create: fn(E) T) T:
	match self:
		ok(value): return value
		error(cause): return create(cause)

// Returns this result when it is successful; for an error, calls `create` once with
// that error and returns the Result it produces.
fn move Result[T, E].or_else(create: fn(move E) T!E) T!E:
	match self:
		ok(value): return ok(value)
		error(cause): return create(cause)

// Transforms only an error, preserving a successful payload unchanged.
fn move Result[T, E].map_error[F](transform: fn(move E) F) T!F:
	match self:
		ok(value): return ok(value)
		error(cause): return error(transform(cause))

// Transforms only a successful payload, preserving an error unchanged.
fn move Result[T, E].map[U](transform: fn(move T) U) U!E:
	match self:
		ok(value): return ok(transform(value))
		error(cause): return error(cause)

// Calls `transform` only on success and returns the Result it produces; an error
// passes through. The error type stays the same.
fn move Result[T, E].and_then[U](transform: fn(move T) U!E) U!E:
	match self:
		ok(value): return transform(value)
		error(cause): return error(cause)

// Returns some with the original success payload, or none for an error.
fn Result[T, E].to_optional() T?:
	if self.is_error(): return none
	return self.get()

// A type that can be compared for equality. Built-in data keeps its value
// semantics; an explicit implementation chooses what counts as the same value.
export interface Equal:
	// Compares this value with another value of the same type.
	fn equals(other: Self) Bool

// A type with a total order; `compare` agrees with `equals` when both are implemented.
export interface Comparable:
	// Orders this value against another of the same type: negative when it sorts
	// before, zero when neither sorts first, positive when it sorts after.
	fn compare(other: Self) Int

// A type whose values can be duplicated. Plain data is Clonable; resource handles,
// natives without a `clone` of their own (a `Regex`, a `Pipe`), function values, and
// any record, alternative or collection holding one of those are not. There is nothing
// to implement: the bound `T: Clonable` makes `value.clone()` available on a type
// parameter.
export interface Clonable:
	// Returns an independent deep copy of this value.
	fn clone() move Self

/*
A type whose values are plain data: no resource, function, interface value or runtime handle
anywhere inside. Bytes cross a boundary only as data, so `json.parse`, `json.stringify` and the
typed JSON stream codecs require `T: Data`. Promises and pipes do not require this bound.

There is nothing to implement. Records and alternatives are `Data` when every field is.
Among the collections, a `List` is `Data` when its element is, and a `Map[String, T]` is `Data` when `T` is (it is a JSON object).
A `Set`, a `Map` with another key type, a `Closeable` type and an `opaque type` are never `Data`.
`JsonValue` is `Data` by declaration, so a dynamic JSON object travels as a `JsonValue`.
*/
export interface Data: ...

// A type with its own text form. `"{value}"`, `print` and a container's text use
// `to_string` when a record or alternative has one; the operation must return a
// `String`. Every standard type with a text form meets this interface the same way, by
// declaring `to_string`.
export interface Stringable:
	// Returns this value as text.
	fn to_string() move String

// A type with a stable hash that is consistent with its `Equal` implementation.
export interface Hashable:
	// Returns a stable hash consistent with `equals` for the same value.
	fn hash() Int

/*
Returns a copy of `cause` with `context` in front of its message, as in
`error(wrap_error("read config", cause))`. The kind and details are kept, and the original message is
added to `details["cause"]`.
*/
export fn wrap_error(context: String, cause: Error) Error:
	var details = cause.details.clone()
	details.add("cause", cause.message.clone())
	return Error(context + ": " + cause.message, cause.kind, details)

// Combines `errors` into one error whose message holds theirs, one per line, and whose
// `count` detail is how many there were. Returns none when the list is empty.
export fn join_errors(errors: List[Error]) Error?:
	if errors.is_empty(): return none

	var text = ""

	for cause in errors:
		if text != "":
			text += "\n"
		text += cause.message

	return Error(text, none, {"count": errors.length().to_string()})

// An Optional copies its payload; `none` stays `none`.
fn Optional[T: Clonable].clone() move T?:
	match self:
		value: return value.clone()
		none: return none

fn Error.clone() move Error:
	return Error(self.message.clone(), self.kind.clone(), self.details.clone())

// A String is its own text.
fn String.to_string() String:
	return self.clone()

// Pads on the left (`pad_start`) or the right (`pad_end`) until the scalar length reaches `target_length`,
// repeating `padding` and cutting its last copy.
fn String.pad_start(target_length: Int, padding: String) String:
	return padding_for(self, target_length, padding) + self

fn String.pad_end(target_length: Int, padding: String) String:
	return self + padding_for(self, target_length, padding)

fn padding_for(text: String, target_length: Int, padding: String) String:
	missing := target_length - text.scalar_length()
	if missing <= 0 or padding.is_empty(): return ""
	// Repeating first makes an oversized request fault at the string limit instead of looping to it.
	source := padding.repeat(missing / padding.scalar_length() + 1)
	var filler = ""
	var count = 0
	for scalar in source.chars():
		if count >= missing: break
		filler += scalar
		count += 1
	return filler

// Plain numbers and flags copy by value: their `clone` is the value itself.
fn Int.clone() Int:
	return self

fn Bool.clone() Bool:
	return self

fn Float.clone() Float:
	return self

fn Float32.clone() Float32:
	return self

fn Int8.clone() Int8:
	return self

fn Int16.clone() Int16:
	return self

fn Int32.clone() Int32:
	return self

fn UInt8.clone() UInt8:
	return self

fn UInt16.clone() UInt16:
	return self

fn UInt32.clone() UInt32:
	return self

fn UInt64.clone() UInt64:
	return self
