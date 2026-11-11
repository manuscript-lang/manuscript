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
	//   EINVAL caller input is invalid, EBADMSG input data is malformed, EOVERFLOW a limit was exceeded,
	//   ERANGE a value or index is out of range, ENOENT not found, EEXIST already exists, ENOTEMPTY directory not empty,
	//   EACCES permission denied, ENOTSUP unsupported, ENOTTY not a terminal, EBADF resource closed,
	//   EIO a task, process or peer ended abnormally, EAGAIN service unavailable, EBUSY resource busy,
	//   ETIMEDOUT a deadline expired, ECANCELED cancelled, EAUTH authentication failed.
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

// Raises a programming fault with the supplied message and stops the current operation.
export fn panic(message: String) Never: ...

// The process-wide output buffer; standard output is flushed at exit
// (crates/ms-rt/src/io.rs).
extern fn msrt_io_write_stdout(text: String) Unit

/*
Writes `value` as text and `end` (a newline unless given) to standard output; `print(chunk, end: "")` streams text without a newline. Generic printing can show a record structurally; pass `value.to_string()` or an interpolated string for its type-specific formatting.
It returns `Unit`. Output to a terminal is flushed at each newline and output to a pipe or file is flushed when the program blocks or exits, so a line printed before a wait is visible while it waits. Use `stdout()` from `@std/io/io.ms` for text without an appended newline, or `stdout_bytes()` for bytes.

<!-- manuscript-example: {"mode":"fragment"} -->
```manuscript
print("total: {total}")
print(order)
```
*/
// ms: effect std.console.write
export fn print[T](value: T, end: String = "\n") Unit:
	msrt_io_write_stdout(value.to_string())
	msrt_io_write_stdout(end)

/*
Data that a write accepts as either text or raw bytes: `String` and `Bytes` both implement it, so
`write_file(path, "text")` and `write_file(path, bytes)` use the same function.
Text is written as its UTF-8 encoding.
*/
export interface Writable:
	// The bytes to write, as a new value the writer may keep.
	fn as_bytes() Bytes

/*
A resource that can be closed. A binding that holds one is closed when its scope ends, on every exit.
The implicit close behaves like `value.close()?`: a failed close becomes the function's error, after the
other bindings of the scopes it leaves have closed. Where the function cannot return an `Error`, or the
close happens inside a holder (a record, list or temporary), a failed close is a fault. If the scope is
already returning an error, that error is kept and the close error is dropped. Call `close()` yourself to
handle the failure; the binding is then consumed.
*/
export interface Closeable:
	/*
    Releases the implementation's resource state; with calls this on every scope exit.
    Cleanup runs during return, expected errors, faults, and cancellation too. A type whose release cannot
    fail returns `ok(unit)`.
    */
	var fn close() Unit!

/*
A source of items that `for` walks: each `next` returns the following item, or `none` once exhausted.
`for item in source:` calls `next` until `none`; a variable or field path advances in place and
keeps its final state, while any other expression is held by the loop alone. `next` should keep
returning `none` after the end. The item is a borrow: it stays valid, and the iterator
unchanged, until the loop body ends; clone it to keep it.
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

impl T?:
	// Returns True when a value is present, and False for none.
	fn is_some() Bool: ...

	// Reports whether this value is absent.
	fn is_none() Bool: ...

	// Returns the payload, or `default` when this is `none`; pass a default or unwrap
	// with `if value := optional:` unless absence is a bug. Without a default, `none`
	// raises a fault.
	fn get(default: T?) T: ...

	// Transforms a present payload; none remains absent.
	fn map[U](transform: fn(T) U) U?: ...

	// Calls transform only when present, returning its Optional unchanged.
	fn and_then[U](transform: fn(T) U?) U?: ...

	// Returns the payload, or calls create once and returns its value only when absent.
	fn get_or_else(create: fn() T) T: ...

	// Calls create once only when absent, returning its Optional unchanged.
	fn or_else(create: fn() T?) T?: ...

	// Returns ok with the original payload, or error with the eager cause. Without a
	// cause, E is Error (kind ENOENT) and the message names the calling source file and
	// line.
	fn ok_or[E = Error](cause: E?) T!E: ...

	// Constructs an error once only for none; present payloads remain unchanged.
	fn ok_or_else[E](create: fn() E) T!E: ...

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

impl T!E:
	// Reports whether this result contains a successful value.
	fn is_ok() Bool: ...

	// Reports whether this result contains an expected error.
	fn is_error() Bool: ...

	// Returns the successful payload, or `default` when this is an error; pass a
	// default or propagate with `?` unless failure is a bug. Without a default, an
	// error raises a fault.
	fn get(default: T?) T: ...

	// Returns the error payload; check `is_error()` first, because a successful result
	// raises a fault.
	fn err() E: ...

	// Returns some with the error payload, or none for a success, so a function that
	// cannot return a Result can handle a failure: `if bad := r.error():`.
	fn error() E?: ...

	// Returns the successful payload, or calls create once with the original error and
	// returns its value.
	fn get_or_else(create: fn(E) T) T: ...

	// Calls create once with the original error only when this is an error, returning
	// its Result.
	fn or_else(create: fn(E) T!E) T!E: ...

	// Transforms only an error, preserving a successful payload unchanged.
	fn map_error[F](transform: fn(E) F) T!F: ...

	// Transforms only a successful payload, preserving an error unchanged.
	fn map[U](transform: fn(T) U) U!E: ...

	// Calls transform only on success. Its result keeps the same error type.
	fn and_then[U](transform: fn(T) U!E) U!E: ...

	// Returns some with the original success payload, or none for an error.
	fn to_optional() T?: ...

// Equality and hashing are ordinary operation interfaces. Built-in data retains
// its value semantics; an explicit implementation selects domain identity.
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
	fn clone() Self

/*
A type whose values are plain data: no resource, function, interface value, or runtime handle
anywhere inside. Bytes cross a boundary only as data, so `json.parse`, `json.stringify`, and the
typed JSON stream codecs require `T: Data`. Promises and pipes do not require this bound.
There is nothing to implement. Records and alternatives are `Data` when every field is; among the collections
only `List` is, when its element is, and a `Map[String, T]` is, when `T` is (it is a JSON object). A `Set` or a `Map` with another key type is never `Data`, nor is a `Closeable` type or an `opaque type`; `JsonValue`
is `Data` by declaration, so a dynamic JSON object travels as a `JsonValue`.
*/
export interface Data: ...

/*
A type whose values are plain words in the runtime, so passing one duplicates it with a bit copy and
the original stays usable. Only an extern type in the standard library declares it, with `impl Copy for T:`;
records and alternatives are copied when every field is, and every other native moves.
*/
export interface Copy: ...

// A type with a stable hash consistent with its `Equal` implementation.
export interface Hashable:
	// Returns a stable hash consistent with `equals` for the same value.
	fn hash() Int

/*
Returns a copy of `cause` with `context` in front of its message: `read(path)?` becomes
`error(wrap_error("read config", cause))`. The kind and details are kept, and the original message is
in `details["cause"]`.
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
