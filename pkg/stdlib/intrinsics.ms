# Source locations for the fixed intrinsic receiver operations.
import StringError from "@std/string.ms"
import NumberError from "@std/numbers.ms"
import Bytes from "@std/bytes.ms"
import Decimal from "@std/decimal.ms"
import Duration from "@std/time.ms"

# Every value has this operation, including unconstrained type parameters.
interface ValueOperations:
    fn toString() -> String

# Data values have a shallow clone returning the concrete receiver type.
interface CloneOperations[T]:
    fn clone() -> T

# String receiver operations use UTF-8 text. Members named `scalar_*` count Unicode
# scalar values; ordinary indices and lengths count Unicode scalar positions unless
# the member explicitly refers to bytes.
interface StringOperations:
    # Counts Unicode scalars, with the same unit as scalar_length.
    get length -> Int
    # Reports whether the text contains no scalars.
    get is_empty -> Bool
    # Returns a fresh list with one String for each Unicode scalar, in order.
    fn chars() -> List[String]
    # Reverses Unicode scalar order; combining sequences/graphemes may change.
    fn reverse() -> String
    # Returns -1, 0 or 1 in lexical scalar order, without locale or normalization.
    fn compare(other: String) -> Int
    # Splits LF and CRLF lines, preserving interior empty lines and standalone CR.
    # Omits a final extra empty item; empty text returns a fresh empty list.
    fn lines() -> List[String]
    # Normalizes using exactly NFC, NFD, NFKC, or NFKD (case-sensitive); max_bytes optionally bounds UTF-8 output.
    # Invalid forms or negative budgets return InvalidInput; exceeded budgets return LimitExceeded.
    fn normalize(
        form: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Concatenates text without changing either operand.
    fn concat(other: String) -> String
    # Tests whether the exact text occurs, without normalization.
    fn contains(value: String) -> Bool
    # Tests whether the receiver ends with this exact suffix.
    fn ends_with(suffix: String) -> Bool
    # Returns locale-independent full Unicode lowercase mapping; the scalar length can change.
    fn lower() -> String
    # Repeats text count times; negative counts/budgets return InvalidInput, exceeded UTF-8 budgets return LimitExceeded.
    fn repeat(
        count: Int,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Transitional compatibility name: omitted or none replaces the first occurrence; an explicit cap can replace more.
    # Use replace_n for a required finite cap; this retained signature has not become a strict first-only operation.
    # An empty old matches at scalar boundaries, and inserted text is not searched again.
    # Zero changes nothing; negative caps retain replace's programming fault.
    fn replace_first(
        old: String,
        new: String,
        max_replacements: Optional[Int] = none
    ) -> String
    # Replaces at most the required number of nonoverlapping literal occurrences; zero leaves text unchanged.
    # Empty old matches at scalar boundaries, inserted text is not rescanned, and negative caps retain replace's programming fault.
    # The count limits replacements, not UTF-8 output bytes; there is no additional allocation budget.
    fn replace_n(old: String, new: String, max_replacements: Int) -> String
    # Compatibility spelling for replace_first, including its explicit replacement cap.
    fn replace(
        old: String,
        new: String,
        max_replacements: Optional[Int] = none
    ) -> String
    # Returns the number of Unicode scalar values in the string.
    get scalar_length -> Int
    # Returns each Unicode scalar value as an integer.
    fn scalar_values() -> List[Int]
    # Selects [start, end) in Unicode scalars; requires 0 <= start <= end <= scalar_length.
    # Negative, inverted, or out-of-range bounds return StringError.OutOfRange.
    fn slice_scalars(start: Int, end: Int) -> Result[String, StringError]
    # Splits exact separators, truncating parts to a supplied nonnegative cap; zero returns [], negatives fault.
    # Empty text with a nonempty separator yields [""]; an empty separator splits into scalars.
    fn split(separator: String, max_parts: Optional[Int] = none) -> List[String]
    # Tests whether the receiver begins with this exact prefix.
    fn starts_with(prefix: String) -> Bool
    # Removes Unicode whitespace at both ends; see the exact whitespace set in the text guide.
    fn trim() -> String
    # Returns locale-independent full Unicode uppercase mapping; the scalar length can change.
    fn upper() -> String
    # Returns a one-scalar String; negative indexes are relative to the end, and invalid indexes return none.
    fn at(index: Int) -> Optional[String]
    # Returns an integer scalar code point; negative indexes are relative to the end, and invalid indexes return none.
    fn scalar_at(index: Int) -> Optional[Int]
    # Returns the first matching Unicode scalar index or none; empty value matches at zero.
    fn index_of(value: String) -> Optional[Int]
    # Returns the last matching Unicode scalar index or none; empty value matches at scalar_length.
    fn last_index_of(value: String) -> Optional[Int]
    # Removes Unicode whitespace at the start.
    fn trim_start() -> String
    # Removes Unicode whitespace at the end.
    fn trim_end() -> String
    # Pads on the left until the scalar length reaches `target_length`.
    # Empty padding or a shorter target leaves text unchanged; max_bytes still bounds UTF-8 output.
    fn pad_start(
        target_length: Int,
        padding: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Pads on the right until the scalar length reaches `target_length`.
    # Empty padding or a shorter target leaves text unchanged; negative targets/budgets return InvalidInput.
    fn pad_end(
        target_length: Int,
        padding: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Replaces every nonoverlapping occurrence; empty old matches at each scalar boundary.
    # max_bytes bounds UTF-8 output; negatives return InvalidInput and exhaustion returns LimitExceeded.
    fn replace_all(
        old: String,
        new: String,
        max_bytes: Optional[Int] = none
    ) -> Result[String, StringError]
    # Selects [start, end) in Unicode scalars; negative bounds are relative to the end.
    # Bounds outside 0 <= start <= end <= scalar_length return StringError.OutOfRange; the receiver is unchanged.
    fn slice(start: Int, end: Int) -> Result[String, StringError]
    # Returns the UTF-8 encoded byte length.
    get byte_length -> Int
    # Encodes the string as UTF-8 bytes.
    fn to_bytes() -> Bytes
    # Parses signed ASCII decimal digits; invalid text or Int overflow returns none.
    fn parse_int() -> Optional[Int]

# Conversion operations for machine-sized integers.
interface IntOperations:
    # Scales this integer to a Duration in milliseconds; out-of-range values fault.
    get milliseconds -> Duration
    # Scales this integer to a Duration in seconds; out-of-range values fault.
    get seconds -> Duration
    # Scales this integer to a Duration in minutes; out-of-range values fault.
    get minutes -> Duration
    # Formats the integer in a radix from 2 through 36 using lowercase digits and a leading `-` for negatives.
    # A radix outside 2 through 36 is a programming fault.
    fn to_string(radix: Int) -> String
    # Converts to the nearest Float; integers beyond 2^53 in magnitude can lose low-order digits.
    fn to_float() -> Float
    # Converts to the exactly equal Decimal; no rounding occurs.
    fn to_decimal() -> Decimal

# Formatting and classification operations for floating-point values.
interface FloatOperations:
    # Formats 1..100 significant digits, preserving trailing zeros; an invalid precision returns NumberError.InvalidInput.
    fn to_precision(precision: Int) -> Result[String, NumberError]
    # Formats scientific notation with 0..100 fractional digits; an invalid count returns NumberError.InvalidInput.
    fn to_exponential(digits: Int) -> Result[String, NumberError]
    # Formats 0..100 fractional digits; magnitude >= 1e21 uses ordinary round-trip notation.
    # Invalid digits return NumberError.InvalidInput; rounding uses binary64 ties to even.
    fn to_fixed(digits: Int) -> Result[String, NumberError]
    # Returns the shortest round-trip representation, including NaN and signed infinities.
    fn to_string() -> String
    # Tests whether the value is NaN.
    get is_nan -> Bool
    # Tests whether the value is neither NaN nor an infinity.
    get is_finite -> Bool
    # Truncates toward zero, or returns none for nonfinite values or Int overflow.
    fn truncate_to_int() -> Optional[Int]

# documentation documentation/standard-library/_index.md
# +++
# title = "Standard library"
# weight = 3
# +++
#
# # Standard library
#
# Start with [imports](imports.md), then learn how to obtain [external services](services.md). [Errors and limits](contracts.md) apply across the library.
#
# Start a [command-line program](cli.md) to use those services in an application.
# Use [testing helpers](testing.md) for assertions.
#
# ## Work with data
#
# - [Text and collections](data.md)
# - [Building values](builders.md)
# - [Numbers and mathematics](math.md)
# - [Data formats](formats.md): JSON, YAML, TOML, CSV, URLs, and HTML
# - [Compression and archives](archive.md)
#
# ## Read, write, and connect
#
# - [Files and paths](filesystem.md), followed by [byte streams](streams.md)
# - [Commands and processes](process.md)
# - [Time and system information](system.md)
# - [Cryptography and randomness](crypto.md)
# - [Sockets and TLS](network.md), then [HTTP](http.md) and [WebSockets](websocket.md)
# - [Logging](logging.md)
#
# Continue with [concurrent work](../concurrency/_index.md) when operations need to run together. Use the [API reference](reference/_index.md) to look up exact declarations and [special call rules](call-rules.md) for additional compiler checks.
# end-documentation

# documentation documentation/standard-library/call-rules.md
# +++
# title = "Special call rules"
# weight = 3
# +++
#
# # Special call rules
#
# The generated reference captures declaration types, bounds, fields, cases, and operations. A few APIs use checker rules beyond an ordinary function signature. These rules are implemented in `pkg/checker/calls.go`; this page must be reviewed when those rules change.
#
# Functions, methods, function values, record/case constructors and contract views accept positional arguments and optional labels under the [ordinary call rules](https://manuscript-lang.github.io/manuscript/core-language/functions/declarations-and-calls/#argument-names). Resolve arguments left to right: only an explicit label selects that parameter; every other expression, including a bare identifier, fills the first unfilled parameter. Defaults do not skip positional slots. Duplicate, unknown, missing and excess arguments remain errors. Supplied arguments evaluate in written order before omitted defaults. Context supplies omitted callback parameter types, and callback bodies may infer generic result types. Single-line callable expression bodies implicitly return their value; multiline bodies keep explicit returns. Function-type labels remain part of type identity. Source functions and native declarations may declare default argument expressions; their evaluation and function-value boundaries are specified in [default arguments](https://manuscript-lang.github.io/manuscript/core-language/functions/declarations-and-calls/#default-arguments).
#
# - `Scheduler(limit: Optional[Int], reporter: Optional[fn(failure: SchedulerFailure) -> Unit], drain: Optional[Duration], history_limit: Optional[Int])` has only optional constructor arguments. Omitted admission and history limits are unbounded. Reporters and start operations are ordinary callbacks; start may be stored as a bound method.
# - `Queue[T]()` creates an unbounded local FIFO. `Queue[T](capacity: 4)` supplies a fixed positive bound through its `capacity: Optional[Int]` constructor argument; supplied payloads are wrapped once under the [optional argument rules](https://manuscript-lang.github.io/manuscript/core-language/types/optionals/#passing-optional-arguments). A nonpositive explicit capacity is a programming fault. Shared access requires `Synchronized[Queue[T]]`.
# - `Synchronized[T](value: T)` stores a value behind a mutex. Its `lock()` returns a `SynchronizedGuard[T]` for `with`; guard get/set require an active acquisition, and close releases it.
# - `Bytes(values: List[Int])` constructs bytes. The runtime checks the byte range.
# - Prelude `List[T]()`, `Map[K, V]()`, and `Set[T]()` construct empty collections, with explicit type arguments or a complete expected type. Their public support types `CollectionError`, `ListEntry`, and `MapEntry` are also in the prelude. `Optional.ok_or`'s default error type `MissingValue` is a prelude declaration too. Explicit standard imports of prelude declarations are rejected; remove those names from the import. Map keys and Set elements still require `Hashable`. `Map.add(key, value)` inserts or replaces a value, returns the receiver and preserves the original key and insertion position.
# - `Task`, `SynchronizedGuard`, `Instant`, `Duration`, `Decimal`, and `OperationId` have no source constructor. Durations use literals; other values come from APIs or conversions.
# - `.clone()` is built in on records, alternatives, List, Map, Set, and Bytes and returns the same concrete data type with separate outer storage. It does not clone nested handles or introduce a method on native services.
# - Records use their listed fields as constructor arguments, with optional labels and declaration-order positional slots. Alternatives construct one listed case. Interfaces describe operations implemented by explicit `impl` declarations; they are capability views rather than concrete resource constructors.
# - TaskGroup.start[T] infers T from its callback or an expected Task[T] result. Saving start as a value requires explicit specialization; Task.join and TaskGroup.join use their source declarations.
# - Native collection methods `map[U]`, `flat_map[U]`, `group_by[K: Hashable]`, `fold[A]`, and `fold_right[A]` infer method type arguments from supplied callbacks/values and unambiguous expected results. Saving a generic method as a value requires explicit specialization, such as `values.map[String]`. Application-defined interface operations remain nongeneric.
# - List equality searches require `Equal`; `to_set` requires `Hashable`; `join` is available only on `List[String]`. These method-specific receiver requirements are explicit in the native bindings; signatures come directly from the receiver declarations.
# - Generic bounds constrain type arguments. There is no sharing bound or separate callable proof.
#
# For lifetime, cancellation, defaults, and host behavior, read the standard library guides. A type signature alone does not establish these guarantees.
# end-documentation

# documentation documentation/standard-library/contracts.md
# +++
# title = "Errors and limits"
# weight = 3
# +++
#
# # Errors and limits
#
# These rules apply across the standard library. Exact types and signatures live in the pinned Manuscript files under `pkg/stdlib/`. The checker reads those files and verifies that native runtime signatures agree with them.
#
# ## Imports and callbacks
#
# Prelude names need no imports; import other functions and types from their modules. Standard imports are pinned with the distribution. They add no additional ambient types, wildcard imports, user-defined generic operations, or automatic imports of host accessors.
#
# Function identity includes the module, so `json/parse`, `bigint/parse`, and `url/parse` remain distinct in generated code. Source import renaming is unsupported; use a helper module if two imports have the same spelling.
#
# Sequential callbacks run under the caller's execution context and may wait for operations. All callbacks are ordinary values and can also be passed to concurrent APIs.
#
# ## Errors
#
# An error is an ordinary value returned in `Result[T, E]`. Standard packages define errors for their own domain, such as `JsonError` and `IoError`; their cases and fields appear in the [generated reference](reference/_index.md). Match the result to handle an error, or use `try` to return it unchanged to a compatible error boundary.
#
# Standard `message()` implementations return human-readable domain diagnostics, such as `filesystem: file or directory not found`. Match error cases for programmatic handling rather than parsing message text. Existing `Failed(message)` and task crash diagnostics are returned unchanged, and logging errors preserve their underlying cause's message. The source-defined TOML/YAML implementations format available line/column positions and parser reason text; they differ from the native generic-domain message helper. Treat their typed fields as the programmatic contract rather than parsing that text.
#
# Nullary errors retain their existing constructors and do not carry the failing path or operation. Add that context at the application boundary when useful, taking care to redact credentials and sensitive paths or contents before displaying it. Explicit message payloads may contain sensitive information and are not automatically redacted.
#
# ### Choosing a failure mode
#
# One rule decides how a standard API reports a mistake:
#
# - **Absence is `Optional`.** A lookup or attempt that may simply find nothing returns `Optional`: `at`, `first`, `get`, `index_of`, `find`, `pop`, `String.parse_int`.
# - **Invalid external data is `Result`.** Input that depends on text, files, the network, or a caller-supplied option that is checked as data returns `Result` with a domain error: `parse` functions, `slice`, formatting options such as `Float.to_fixed`, `repeat` and `pad` counts, `BigInt.divide`.
# - **A violated documented precondition is a fault.** Strict edits, constructors, and primitive operators fault: `List.set`, `remove`, `insert`, `splice`, `Bytes.with_value`, `Int` `/` and `%`, `Duration.divide`, `Int.to_string(radix:)`, `Queue(capacity:)`. Validate dynamic values first.
#
# Idempotent removal is not an edit: `Map.remove` and `Set.remove` of an absent key are no-ops, while `List.remove(index:)` addresses a position and faults when it does not exist. A signature does not carry this choice; each declaration's comment names its mode. `String.parse_int` is a reason-discarding convenience; use `numbers.parse_int` or `bigint.parse` when the radix or failure reason matters.
#
# Faults state the operation, the offending argument with its value, and the valid range, for example `List.insert: index 9 is outside 0..3`. A new API follows this rule and message shape. Existing signatures stay as they are, so aligning an API that disagrees (for example moving `Int.to_string(radix:)` to `Result`) is a deliberate breaking change decided separately.
#
# ### Error details
#
# Put typed information directly in an error record or alternative case. Each field has its own type. A domain error does not need an `Error` implementation to be returned or propagated.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import panic from "@std/faults.ms"
#
# type ReadError:
#     path: String
#     attempt: Int
#     retryable: Bool
#
# fn failed_read() -> Result[Unit, ReadError]:
#     return error(ReadError(path: "settings.json", attempt: 2, retryable: true))
#
# test "read typed error fields":
#     match failed_read():
#         ok(_):
#             return panic(message: "failed read succeeded")
#         error(cause):
#             if cause.path != "settings.json" or cause.attempt != 2 or not cause.retryable:
#                 return panic(message: "missing error details")
# ```
#
# Records and their fields retain ordinary mutable value semantics. Add a cause field when an error needs to preserve another failure; its type can be that specific domain error.
#
# ### Several error types at one boundary
#
# Use `Error` from `@std/errors.ms` when a boundary should handle several error types through one `message() -> String` operation. Standard errors implement this interface; custom errors can declare an ordinary `impl Error` in their defining module.
#
# Pass or return a specific error directly where `Error` is expected. Functions returning `Result[T, Error]` can use `try` with specific standard errors, or forward a `Result[T, SpecificError]` with the same success type. The original error and its fields are retained. Call `message()` for a diagnostic, or use a [contract type match](../core-language/control-flow/pattern-matching.md#contract-type-patterns) to recover the concrete error. See [common error boundaries](../core-language/errors/results.md#a-common-error-boundary) for an example.
#
# Unrelated domain errors still need an explicit translation. The Error interface does not constrain Result's error parameter or turn faults and cancellation into expected failures.
#
# ### Shared error categories
#
# `category(cause: Error) -> Optional[ErrorCategory]` from `@std/errors.ms` queries a portable category for a recognized standard error. It keeps the original domain value and payload, calls no error operation, and never parses messages. It does not add an operation to the `Error` interface; existing custom implementations remain valid.
#
# | Standard case | Category |
# | --- | --- |
# | `InvalidInput`, `InvalidData`, `LimitExceeded` | The same-name category |
# | `NotFound`, `AlreadyExists`, `PermissionDenied` | The same-name category |
# | `Unsupported`, `Closed`, `Unavailable` | The same-name category |
# | `Timeout` | `Timeout` |
# | Custom errors or other domain cases | `none` |
#
# `Unavailable` does not imply a missing resource or denied permission. Cases such as `Failed(message)`, `Full`, `OutputLimit`, `OutOfRange`, `AuthenticationFailed`, `Cancelled`, YAML `UnsupportedFeature`, and wrapped logging causes remain domain-specific and return `none`. In particular, a timeout described only by an `IoError.Failed` message is not classified as `Timeout`. Use the concrete domain type when these distinctions matter.
#
# <!-- manuscript-example: {"mode":"test"} -->
# ```manuscript
# import {category, ErrorCategory} from "@std/errors.ms"
# import FileSystemError from "@std/fs.ms"
# import panic from "@std/faults.ms"
#
# fn is_missing(cause: Error) -> Bool:
#     return category(cause) == some(ErrorCategory.NotFound)
#
# test "query keeps the original error":
#     let cause = FileSystemError.NotFound
#     if not is_missing(cause): return panic("missing category")
#     if cause != FileSystemError.NotFound: return panic("changed domain value")
# ```
#
# | Situation | Behavior |
# | --- | --- |
# | Malformed data or unavailable OS service | Return an expected Result error. |
# | Missing value | Use Optional. |
# | Illegal String, List, or Bytes `slice` bounds | Return the declared Result error: StringError.OutOfRange or CollectionError.OutOfRange. |
# | Broken programming assumptions or explicit invariant violation | Produce a programming fault. |
# | Parent cancellation | Unwind; do not turn cancellation into EOF or a domain error. |
# | Local network deadline expires | NetworkError/HttpError use `Timeout`; Connection I/O uses `IoError.Failed` with a timeout diagnostic. Command/group deadlines use `TimedOut`. |
#
# Collection mutation bounds, byte values, integer-formatting radices, and supplied queue capacities fault when their documented call preconditions fail. Their diagnostics name the operation and parameter, show the original offending argument, and state the valid range. For example, `Bytes.with_value: value must be between 0 and 255, found 300` distinguishes a value failure from an index failure.
#
# Negative indexes in `at`, List `set`/`remove`, and Bytes `with_value` are relative to the end. Empty collections have no valid update/removal index. List `fill` and `copy_within` require nonnegative `0 <= start <= end <= length`; List `splice` requires `0 <= start <= length` and `0 <= delete_count <= length - start`. The legacy List spellings `with_value`, `without`, and `with_values` retain the same mutation bounds and faults; see the [naming migration](../core-language/types/collections.md#naming-and-migration).
#
# String, List, and Bytes `slice(start:, end:)` return Result and resolve each negative bound relative to the end before requiring `0 <= start <= end <= length`. String uses its Unicode scalar length; List uses elements and Bytes uses bytes. Invalid bounds return `StringError.OutOfRange` for String or `CollectionError.OutOfRange` for List/Bytes, without clamping or a programming fault. Successful List slices have independent shallow outer storage; immutable Bytes slices may share backing storage. See the [half-open slice rules](../core-language/basics/text-and-bytes.md#half-open-slices) for exact contracts, including `slice_scalars`.
#
# If cancellation wins before a newly acquired resource is delivered, native acquisition releases that resource. Delivered socket handles use `with` and synchronized close admission. Retaining another reference never extends the open lifetime.
#
# ### Host views and error translation
#
# Error case sets describe each domain, even when case names coincide. Filesystem, system, and process calls share mappings for native not-found, already-existing, permission-denied and unsupported errors to their own `NotFound`, `AlreadyExists`, `PermissionDenied` and `Unsupported` cases. Validated caller input produces `InvalidInput`; unclassified OS failures retain host text in `Failed(message)`. Operation-specific mappings and validation still apply.
#
# | Boundary | Result contract |
# | --- | --- |
# | `io.Files.open` | Read-only File view; native open failures become `IoError.Unavailable`, including missing paths and permissions. |
# | `FileSystem.open` / `open_flags` | Read/write/positional FileHandle with FileSystemError cases. |
# | `FileHandle.reader()` / `writer()` | Shared-handle stream adapters retain `Closed`/`InvalidInput`; other filesystem cases become `IoError.Failed` with their case name, or the original Failed text. |
# | Stream helpers | Preserve returned IoError case/payload. EOF is absence/empty data, not a failure; cancellation unwinds. |
# | `Error` view | Retains the concrete error value for type matching, while exposing only `message()` as a common operation. |
# | Scheduler callbacks | Use `Result[Unit, Error]`; `SchedulerFailure.Failed.cause` is the returned `Error` with its concrete type and payload intact, so reporters can match it or call `category`. Return `TextError.Text(message)` from `@std/errors.ms` for intentional text. `Crashed` carries a fault message. |
#
# The absence of a case in PathError, CryptoError, RegexError, UrlError, or JsonError does not authorize inventing a generic Failed/LimitExceeded at that boundary. The optional category query preserves those distinctions. A scheduler error migration still needs an explicit API and compatibility decision. Every timeout case is spelled `Timeout`, and every write returns `Unit`.
#
# ### Native I/O success and EOF
#
# Native WriteStream, Connection, and FileHandle writes accept all supplied bytes on success. Errors/cancellation may leave a prefix and do not report its size. Acceptance does not guarantee disk durability or peer processing. Source WriteStream implementations may buffer until flush; native stdout/stderr flush is a no-op, while the file-handle writer adapter flushes with file sync. Commands and `read_file`/`read_all` buffer whole results in memory; chunk readers, directory cursors, sockets, and streaming HTTP expose incremental delivery.
#
# | Reader | EOF contract |
# | --- | --- |
# | File, ReadStream, Connection, FileHandle.read | `ok(none)` once no data remains; a final positive chunk can precede EOF. |
# | FileHandle.read_at | `ok(Bytes)` with a short final chunk or empty bytes beyond EOF; no sequential position change. |
# | FileSystem.read_file, FileHandle.read_file, io.read_all | Whole/remaining content on success; empty content gives empty Bytes. |
# | io.read_line | `none` only when EOF precedes all data; final unterminated text is a line. |
# | Directory.read | `none` once entries are exhausted. |
#
# See [file positions/adapters](filesystem.md#file-reads-and-writes), [stream helpers](process.md#stream-helpers), and [socket deadlines](network.md#datagrams-and-operation-timeouts) for exact bounds and error identities.
#
# ## Optional limits and deadlines
#
# Limit and timeout parameters use `Optional[T] = none`. Omission or explicit `none` adds no operation budget or deadline. Supply a plain limit or duration to enforce a budget; the compiler wraps it under the [optional argument rules](../core-language/types/optionals.md#passing-optional-arguments). Optional limit fields in standard option records may also be omitted; `JsonLimits()` and `ArchiveLimits()` have no imposed budgets.
#
# ```manuscript
# import StringError from "@std/string.ms"
#
# fn repeated() -> Result[String, StringError]:
#     let unlimited = try "ab".repeat(count: 3)
#     return "ab".repeat(count: 3, max_bytes: 6)
# ```
#
# Supplied negative bounds are invalid. Zero retains each operation's declared meaning: an output budget allows no output, a zero timeout expires immediately, split's zero limit returns no parts, a zero `max_digits` or `max_rows` budget admits no digits or rows (`LimitExceeded` when input exceeds it), a negative limit on `split` or `replace` faults with a message naming the operation and parameter, and a queue's supplied capacity must be positive. Limits are validated even when another limit is omitted.
#
# Invalid supplied Scheduler `limit`, `history_limit`, or `drain`, TaskGroup `timeout`, and `sleep` duration values fault with the operation, parameter, original value, and valid range. Duration arguments are reported in nanoseconds. Omitted/`none` bounds retain their existing meaning; zero is allowed for history, drain, timeout, and sleep, while a supplied Scheduler admission limit must be positive.
#
# A chunk read's `max_bytes` requests a chunk size; it does not cap the total stream. Omitted reads use a 64 KiB buffer, and datagrams use their protocol maximum. Signal and file-watcher buffers retain finite default buffer sizes, rather than imposing a total event budget. Protocol restrictions, numeric representability, filesystem authority, and execution cancellation still apply.
#
# Socket reads/writes, datagram send/receive, and listener accept have one operation each with an optional `timeout`. The caller's execution cancellation remains effective with no local timeout. HTTP request/body limits and server admission are likewise optional; omitted server admission does not allocate a fixed-capacity queue.
#
# ## Bounds and native limits
#
# Byte, item, and depth limits are optional; omission adds no operation cap. Supplied limits are nonnegative unless a package requires a positive value. Budget exhaustion returns an error; split limits intentionally truncate the returned parts.
#
# A limit on a function's output does not bound input already allocated by the caller. Some native operations also allocate before they can check a limit: CSV may parse one record, ZIP may read the central directory, and logging may construct a full record. Bound source reads and consult each package's behavior section.
#
# | Facility | Native limit |
# | --- | --- |
# | JSON | Supplied depth budgets are respected; cycles cannot be serialized. |
# | HTTP | Header limits are optional; the native reader remains constrained by integer representability. |
# | Allocated lists | `filled` and `range` return `LimitExceeded` beyond 2^28 items, even with a larger `max_items`. |
# | Allocated strings | `repeat`, `pad_start` and `pad_end` return `LimitExceeded` beyond 1 GiB, even with a larger `max_bytes`. |
# | Entropy | 16 MiB per call. |
# | UDP receive | At most 65535 bytes. |
#
# These limits do not form a general memory or CPU sandbox.
#
# ## Cancellation and partial effects
#
# Native loops check cancellation between bounded chunks. A single math, regex, big-integer, directory, resolver, or OS call may delay cancellation until it returns. There is no forced termination.
#
# Writing, copying, or removing data can fail after changing an external prefix. Cancellation and errors do not imply rollback or a transaction.
#
# ## Access to external services
#
# Imported host accessors supply filesystem, entropy, wall-clock, system, network, and command services. Source fakes implement the same contracts with explicit contract views.
#
# Pure codec, path, math, and hash functions grant no OS access. Native CLI services use the process's OS permissions. Filesystem subtree restrictions are not implemented; `Network.restrict` narrows destination access. Imported host accessors obtain services from the current execution. HTTP and socket operations retain their service interfaces and TLS verification.
#
# Networking includes DNS, Unix sockets, verified TLS, streaming HTTP, and WebSockets. HTTP/3 is outside the supported scope. Native builds bundle pinned dependency sources and licenses rather than fetching packages.
# end-documentation

# documentation documentation/standard-library/imports.md
# +++
# title = "Standard imports"
# weight = 1
# +++
#
# # Standard imports
#
# Most standard names need an explicit import. An imported function or type follows the same scope rules as one declared in your own module.
#
# ```manuscript
# import {filesystem, FileSystemError} from "@std/fs.ms"
# ```
#
# Import a type outside the prelude when naming it in an annotation or constructor. A type inferred from a return value needs no separate import unless you name it in source. The [API reference](reference/_index.md) lists each module's declarations.
#
# ## Names and identity
#
# `Bool`, `Int`, `Float`, `String`, `Unit`, `Never`, `Equal`, `Hashable`, `Optional`, `Result`, `Error`, `List`, `Map`, `Set`, `CollectionError`, `ListEntry`, `MapEntry`, and `MissingValue` are available through the prelude. The `some`, `none`, `ok`, and `error` cases and the cases of `CollectionError` and `MissingValue` are available through their prelude types. Every other standard name comes from an explicit `@std/…` import. Importing one name does not expose other names from that module; wildcard imports are unsupported.
#
# `@std` is the reserved directory supplied by the compiler distribution. Standard identities are independent of its installation path. Application declarations and imports may shadow the prelude data types and `Error`; matching a standard spelling does not give a type standard behavior. `Equal` and `Hashable` retain fixed identities. See the canonical [module scope rules](../core-language/modules/declarations.md#names-and-declaration-order).
#
# ## Migrating prelude imports
#
# Explicit standard imports of the source-backed prelude declarations above now fail with `MS2003`. Delete a singleton import; in a grouped import, remove only those names and keep unrelated APIs such as `ListBuilder`, `range`, or `ErrorCategory`. The editor offers a removal quick fix. Application imports, including project aliases to same-named application types, keep their ordinary meaning.
#
# `CollectionError` is now visible in every module. If another visible alternative also defines `InvalidInput`, `LimitExceeded`, or `OutOfRange`, qualify expression constructors as `CollectionError.OutOfRange` or `OtherError.OutOfRange`. The same rule applies to `MissingValue.Missing` and another visible type's `Missing` case. Match patterns continue to select cases from their scrutinee type.
#
# ## Syntax that uses standard types
#
# - Bracket list literals use the standard `List` from the prelude.
# - A `d`-suffixed number needs `Decimal` from `@std/decimal.ms`.
# - `try` recognizes the standard `Result` type.
# - `with` uses the standard `Closeable` implementation or an interface declaring the exact `close() -> Unit` operation. Using an already-typed resource does not require an otherwise unused `Closeable` import.
#
# Application code cannot add methods or implementations to intrinsic or standard-library types. Source types can implement standard interfaces according to the [implementation rules](../core-language/types/contracts.md#coherence-and-visibility).
#
# ## Types and service values
#
# Importing `FileSystem` supplies a type. Calling the imported `filesystem()` function obtains the current execution's filesystem service. The same distinction applies to clocks, network access, and process services. Continue with [external services](services.md).
# end-documentation

# Contributor notes: source ownership and editor integration.
# # Standard-library declarations
#
# The `.ms` files here define public types, fields, cases, function signatures, and receiver operations. The compiler reads this pinned source directly. Modules with ordinary function or implementation bodies are written in Manuscript and checked and lowered with each importing program. Go supplies the native implementations for declaration-only modules; integration tests check that their calling signatures agree with the Manuscript declarations.
#
# ## Which file defines what?
#
# - The `.ms` files define the type schemas and public API.
# - Native functions dispatch to `module/name`; `bindings.json` lists only the exceptions under `function_overrides`, and maps receiver-operation and implementation identities directly to native dispatch. It also records method-specific receiver requirements, such as `Equal` for list searches and `String` for list joining; it does not duplicate operation signatures or type schemas.
# - `intrinsics.ms` contains private operation declarations for primitive receivers and the universal `toString()` method.
# - Native receiver signatures appear once, on their type or intrinsic interface. TaskGroup and Task[T] use ordinary generic declarations; no private free-function declarations are needed for their implementations.
#
# These files use ordinary Manuscript syntax. Runtime functions and receiver operations have empty function bodies, written with the usual colon, such as `export fn commands() -> Commands:`. Opaque type schemas use empty declarations such as `export type Duration:`. Interface signatures remain signatures, and `bindings.json` maps the declarations to native implementations. The checker verifies implementation rules and native signatures. There is no library-only parser mode or `native` keyword. Ordinary record fields may have default expressions.
#
# Nongeneric native defaults are checked expressions in these declarations. Generated source preparation evaluates omitted defaults before calling the unchanged native ABI; mutable values are created afresh. Existing `Optional[T] = none` adapters keep their native path, including generic native declarations. Other native generic expression defaults are rejected until their substitution contract is implemented; source generic defaults remain supported. Do not add another default schema to `bindings.json` or the runtime.
#
# This slice permits expression field defaults on ordinary records. Opaque native constructors retain their existing defaults until delivery/disposal is designed. Standard interface expression defaults are restricted to closed literals or bytes converted from literal text, so preparing inherited defaults before an implementation's own defaults cannot reorder visible effects or read a still-missing parameter. Dependent/effectful inherited defaults need one combined ordered prologue before that restriction is expanded. Recursive native default expansion is rejected during lowering; use a source wrapper for recursive defaults.
#
# Direct calls supplying every new expression default keep the original dispatch, including old `none` omission slots. Stateless free-function and ordinary-record default callables are cached through the existing Lazy mechanism; default expressions and mutable storage are still evaluated per call. Receiver-bound callables retain their captured receiver and have a runtime slot check.
#
# Modules with executable bodies use the ordinary checker and need no entries in `bindings.json`. Imports include their reachable source implementations once, with the same public visibility and type identities as application modules.
#
# Keep a module's implementation ownership consistent: adding an executable body marks the whole module as source-owned. A typed adapter in an existing declaration-only module should use its native binding path; one source helper body does not preserve that module's other native declarations or nominal identities.
#
# ## Editor navigation
#
# Editor adapters can use `tooling.StandardDeclarations` and `tooling.NavigationAt` to find hover and definition locations in `@std` documents.
#
# Hover documentation lives in contiguous `#` comments immediately above a public declaration or operation. The LSP renders this text as Markdown beneath the checked Manuscript signature. Keep the opening sentence direct, then describe behavior that is not clear from the signature: units, defaults, limits, mutation, end-of-stream behavior, and expected errors. Inline Markdown such as code spans is supported.
#
# The generated Markdown/JSON reference also reads comments above fields, cases, and receiver/implementation operations. Keep each block at the member's indentation; a blank line detaches it. JSON preserves the original string arrays and adds structured `members` descriptions. Document case payloads by placing each parameter and its comment on an indented line inside the parentheses; a case description does not describe its fields implicitly.
#
# `make docs` and `make docs-check` report description counts and enforce the description gate. `make docs-coverage` writes the complete inventory to `.artifacts/stdlib-doc-coverage.json`, including prelude aliases. Presence and structural quality are separate counts: empty text, placeholders, very terse labels, and name/kind restatements fail quality checks. Review each description against source/native behavior; passing structural checks cannot prove semantic accuracy or measure a separate tutorial's coverage.
#
# `pkg/tooling/docgen/description_backlog.json` records exact existing gaps during #176's sweep. This temporary list only shrinks: new gaps fail, invalid prose cannot use it, and described/removed entries make the old key stale. It is not an internal/generated exemption. Public synthetic primitive entries require descriptions too. Private `ValueOperations`/`CloneOperations` are implementation declarations; their universal calls have canonical call rules rather than becoming importable interfaces. No blanket public-description exemption is supported.
#
# These APIs provide navigation data; an editor integration must supply its own LSP server and transport.
#
# For user-facing imports and API behavior, see the [standard-library guide](../../documentation/standard-library/_index.md).
#
# Filesystem and path contracts are described in the [filesystem guide](../../documentation/standard-library/filesystem.md); [system](../../documentation/standard-library/system.md), [process](../../documentation/standard-library/process.md), and [scheduling](../../documentation/concurrency/scheduling.md) have their own guides. Platform helpers in `internal/hostos/` are bundled with native dependency sources.
#
# Time values and sequential `sleep` live in `@std/time.ms`. `@std/tasks.ms` owns `Scheduler`, which manages immediate, delayed, and repeating work through one operation-ID lifecycle, plus TaskGroup, Task[T], cancellation checks, and scheduler yielding. Limits and deadlines use optional values; receiver operations are the single public API for existing data.
