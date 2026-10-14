+++
title = "Errors and limits"
weight = 3
+++

# Errors and limits

These rules apply across the standard library. Exact types and signatures live in the pinned Manuscript files under `pkg/stdlib/`. The checker reads those files and verifies that native runtime signatures agree with them.

## Imports and callbacks

Prelude names need no imports; import other functions and types from their modules. Standard imports are pinned with the distribution. They add no additional ambient types, wildcard imports, user-defined generic operations, or automatic imports of host accessors.

Function identity includes the module, so `json/parse`, `bigint/parse`, and `url/parse` remain distinct in generated code. Source import renaming is unsupported; use a helper module if two imports have the same spelling.

Sequential callbacks run under the caller's execution context and may wait for operations. All callbacks are ordinary values and can also be passed to concurrent APIs.

## Errors

An error is an ordinary value returned in `Result[T, E]`. Standard packages define errors for their own domain, such as `JsonError` and `IoError`; their cases and fields appear in the [generated reference](reference/_index.md). Match the result to handle an error, or use `try` to return it unchanged to a compatible error boundary.

Standard `message()` implementations return human-readable domain diagnostics, such as `filesystem: file or directory not found`. Match error cases for programmatic handling rather than parsing message text. Existing `Failed(message)` and task crash diagnostics are returned unchanged, and logging errors preserve their underlying cause's message. The source-defined TOML/YAML implementations format available line/column positions and parser reason text; they differ from the native generic-domain message helper. Treat their typed fields as the programmatic contract rather than parsing that text.

Nullary errors retain their existing constructors and do not carry the failing path or operation. Add that context at the application boundary when useful, taking care to redact credentials and sensitive paths or contents before displaying it. Explicit message payloads may contain sensitive information and are not automatically redacted.

### Choosing a failure mode

One rule decides how a standard API reports a mistake:

- **Absence is `Optional`.** A lookup or attempt that may simply find nothing returns `Optional`: `at`, `first`, `get`, `index_of`, `find`, `pop`, `String.parse_int`.
- **Invalid external data is `Result`.** Input that depends on text, files, the network, or a caller-supplied option that is checked as data returns `Result` with a domain error: `parse` functions, `slice`, formatting options such as `Float.to_fixed`, `repeat` and `pad` counts, `BigInt.divide`.
- **A violated documented precondition is a fault.** Strict edits, constructors, and primitive operators fault: `List.set`, `remove`, `insert`, `splice`, `Bytes.with_value`, `Int` `/` and `%`, `Duration.divide`, `Int.to_string(radix:)`, `Queue(capacity:)`. Validate dynamic values first.

Idempotent removal is not an edit: `Map.remove` and `Set.remove` of an absent key are no-ops, while `List.remove(index:)` addresses a position and faults when it does not exist. A signature does not carry this choice; each declaration's comment names its mode. `String.parse_int` is a reason-discarding convenience; use `numbers.parse_int` or `bigint.parse` when the radix or failure reason matters.

Faults state the operation, the offending argument with its value, and the valid range, for example `List.insert: index 9 is outside 0..3`. A new API follows this rule and message shape. Existing signatures stay as they are, so aligning an API that disagrees (for example moving `Int.to_string(radix:)` to `Result`) is a deliberate breaking change decided separately.

### Error details

Put typed information directly in an error record or alternative case. Each field has its own type. A domain error does not need an `Error` implementation to be returned or propagated.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import panic from "@std/faults.ms"

type ReadError:
    path: String
    attempt: Int
    retryable: Bool

fn failed_read() -> Result[Unit, ReadError]:
    return error(ReadError(path: "settings.json", attempt: 2, retryable: true))

test "read typed error fields":
    match failed_read():
        ok(_):
            return panic(message: "failed read succeeded")
        error(cause):
            if cause.path != "settings.json" or cause.attempt != 2 or not cause.retryable:
                return panic(message: "missing error details")
```

Records and their fields retain ordinary mutable value semantics. Add a cause field when an error needs to preserve another failure; its type can be that specific domain error.

### Several error types at one boundary

Use `Error` from `@std/errors.ms` when a boundary should handle several error types through one `message() -> String` operation. Standard errors implement this interface; custom errors can declare an ordinary `impl Error` in their defining module.

Pass or return a specific error directly where `Error` is expected. Functions returning `Result[T, Error]` can use `try` with specific standard errors, or forward a `Result[T, SpecificError]` with the same success type. The original error and its fields are retained. Call `message()` for a diagnostic, or use a [contract type match](../core-language/control-flow/pattern-matching.md#contract-type-patterns) to recover the concrete error. See [common error boundaries](../core-language/errors/results.md#a-common-error-boundary) for an example.

Unrelated domain errors still need an explicit translation. The Error interface does not constrain Result's error parameter or turn faults and cancellation into expected failures.

### Shared error categories

`category(cause: Error) -> Optional[ErrorCategory]` from `@std/errors.ms` queries a portable category for a recognized standard error. It keeps the original domain value and payload, calls no error operation, and never parses messages. It does not add an operation to the `Error` interface; existing custom implementations remain valid.

| Standard case | Category |
| --- | --- |
| `InvalidInput`, `InvalidData`, `LimitExceeded` | The same-name category |
| `NotFound`, `AlreadyExists`, `PermissionDenied` | The same-name category |
| `Unsupported`, `Closed`, `Unavailable` | The same-name category |
| `Timeout`, `TimedOut` | `Timeout` |
| Custom errors or other domain cases | `none` |

`Unavailable` does not imply a missing resource or denied permission. Cases such as `Failed(message)`, `Full`, `OutputLimit`, `OutOfRange`, `AuthenticationFailed`, `Cancelled`, YAML `UnsupportedFeature`, and wrapped logging causes remain domain-specific and return `none`. In particular, a timeout described only by an `IoError.Failed` message is not classified as `Timeout`. Use the concrete domain type when these distinctions matter.

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import {category, ErrorCategory} from "@std/errors.ms"
import FileSystemError from "@std/fs.ms"
import panic from "@std/faults.ms"

fn is_missing(cause: Error) -> Bool:
    return category(cause) == some(ErrorCategory.NotFound)

test "query keeps the original error":
    let cause = FileSystemError.NotFound
    if not is_missing(cause): return panic("missing category")
    if cause != FileSystemError.NotFound: return panic("changed domain value")
```

| Situation | Behavior |
| --- | --- |
| Malformed data or unavailable OS service | Return an expected Result error. |
| Missing value | Use Optional. |
| Illegal String, List, or Bytes `slice` bounds | Return the declared Result error: StringError.OutOfRange or CollectionError.OutOfRange. |
| Broken programming assumptions or explicit invariant violation | Produce a programming fault. |
| Parent cancellation | Unwind; do not turn cancellation into EOF or a domain error. |
| Local network deadline expires | NetworkError/HttpError use `Timeout`; Connection I/O uses `IoError.Failed` with a timeout diagnostic. Command/group deadlines use `TimedOut`. |

Collection mutation bounds, byte values, integer-formatting radices, and supplied queue capacities fault when their documented call preconditions fail. Their diagnostics name the operation and parameter, show the original offending argument, and state the valid range. For example, `Bytes.with_value: value must be between 0 and 255, found 300` distinguishes a value failure from an index failure.

Negative indexes in `at`, List `set`/`remove`, and Bytes `with_value` are relative to the end. Empty collections have no valid update/removal index. List `fill` and `copy_within` require nonnegative `0 <= start <= end <= length`; List `splice` requires `0 <= start <= length` and `0 <= delete_count <= length - start`. The legacy List spellings `with_value`, `without`, and `with_values` retain the same mutation bounds and faults; see the [naming migration](../core-language/types/collections.md#naming-and-migration).

String, List, and Bytes `slice(start:, end:)` return Result and resolve each negative bound relative to the end before requiring `0 <= start <= end <= length`. String uses its Unicode scalar length; List uses elements and Bytes uses bytes. Invalid bounds return `StringError.OutOfRange` for String or `CollectionError.OutOfRange` for List/Bytes, without clamping or a programming fault. Successful List slices have independent shallow outer storage; immutable Bytes slices may share backing storage. See the [half-open slice rules](../core-language/basics/text-and-bytes.md#half-open-slices) for exact contracts, including `slice_scalars`.

If cancellation wins before a newly acquired resource is delivered, native acquisition releases that resource. Delivered socket handles use `with` and synchronized close admission. Retaining another reference never extends the open lifetime.

### Host views and error translation

Error case sets describe each domain, even when case names coincide. Filesystem, system, and process calls share mappings for native not-found, already-existing, permission-denied and unsupported errors to their own `NotFound`, `AlreadyExists`, `PermissionDenied` and `Unsupported` cases. Validated caller input produces `InvalidInput`; unclassified OS failures retain host text in `Failed(message)`. Operation-specific mappings and validation still apply.

| Boundary | Result contract |
| --- | --- |
| `io.Files.open` | Read-only File view; native open failures become `IoError.Unavailable`, including missing paths and permissions. |
| `FileSystem.open` / `open_flags` | Read/write/positional FileHandle with FileSystemError cases. |
| `FileHandle.reader()` / `writer()` | Shared-handle stream adapters retain `Closed`/`InvalidInput`; other filesystem cases become `IoError.Failed` with their case name, or the original Failed text. |
| Stream helpers | Preserve returned IoError case/payload. EOF is absence/empty data, not a failure; cancellation unwinds. |
| `Error` view | Retains the concrete error value for type matching, while exposing only `message()` as a common operation. |
| Scheduler callbacks | Currently use `Result[Unit, String]`; `SchedulerFailure.Failed.cause` is text, and Crashed carries a fault message. No domain-error view is implied. |

The absence of a case in PathError, CryptoError, RegexError, UrlError, or JsonError does not authorize inventing a generic Failed/LimitExceeded at that boundary. The optional category query preserves those distinctions. A scheduler error migration, timeout case rename, or unified write result still needs an explicit API and compatibility decision.

### Native I/O success and EOF

Native WriteStream, Connection, and FileHandle writes accept all supplied bytes on success. FileHandle count results report the complete input length; Unit results omit that count. Errors/cancellation may leave a prefix and do not report its size. Acceptance does not guarantee disk durability or peer processing. Source WriteStream implementations may buffer until flush; native stdout/stderr flush is a no-op, while the file-handle writer adapter flushes with file sync. Commands and `read_file`/`read_all` buffer whole results in memory; chunk readers, directory cursors, sockets, and streaming HTTP expose incremental delivery.

| Reader | EOF contract |
| --- | --- |
| File, ReadStream, Connection, FileHandle.read | `ok(none)` once no data remains; a final positive chunk can precede EOF. |
| FileHandle.read_at | `ok(Bytes)` with a short final chunk or empty bytes beyond EOF; no sequential position change. |
| FileSystem.read_file, FileHandle.read_file, io.read_all | Whole/remaining content on success; empty content gives empty Bytes. |
| io.read_line | `none` only when EOF precedes all data; final unterminated text is a line. |
| Directory.read | `none` once entries are exhausted. |

See [file positions/adapters](filesystem.md#file-reads-and-writes), [stream helpers](process.md#stream-helpers), and [socket deadlines](network.md#datagrams-and-operation-timeouts) for exact bounds and error identities.

## Optional limits and deadlines

Limit and timeout parameters use `Optional[T] = none`. Omission or explicit `none` adds no operation budget or deadline. Supply a plain limit or duration to enforce a budget; the compiler wraps it under the [optional argument rules](../core-language/types/optionals.md#passing-optional-arguments). Optional limit fields in standard option records may also be omitted; `JsonLimits()` and `ArchiveLimits()` have no imposed budgets.

```manuscript
import StringError from "@std/string.ms"

fn repeated() -> Result[String, StringError]:
    let unlimited = try "ab".repeat(count: 3)
    return "ab".repeat(count: 3, max_bytes: 6)
```

Supplied negative bounds are invalid. Zero retains each operation's declared meaning: an output budget allows no output, a zero timeout expires immediately, split's zero limit returns no parts, a zero `max_digits` or `max_rows` budget admits no digits or rows (`LimitExceeded` when input exceeds it), a negative limit on `split` or `replace` faults with a message naming the operation and parameter, and a queue's supplied capacity must be positive. Limits are validated even when another limit is omitted.

Invalid supplied Scheduler `limit`, `history_limit`, or `drain`, TaskGroup `timeout`, and `sleep` duration values fault with the operation, parameter, original value, and valid range. Duration arguments are reported in nanoseconds. Omitted/`none` bounds retain their existing meaning; zero is allowed for history, drain, timeout, and sleep, while a supplied Scheduler admission limit must be positive.

A chunk read's `max_bytes` requests a chunk size; it does not cap the total stream. Omitted reads use a 64 KiB buffer, and datagrams use their protocol maximum. Signal and file-watcher buffers retain finite default buffer sizes, rather than imposing a total event budget. Protocol restrictions, numeric representability, filesystem authority, and execution cancellation still apply.

Socket reads/writes, datagram send/receive, and listener accept have one operation each with an optional `timeout`. The caller's execution cancellation remains effective with no local timeout. HTTP request/body limits and server admission are likewise optional; omitted server admission does not allocate a fixed-capacity queue.

## Bounds and native limits

Byte, item, and depth limits are optional; omission adds no operation cap. Supplied limits are nonnegative unless a package requires a positive value. Budget exhaustion returns an error; split limits intentionally truncate the returned parts.

A limit on a function's output does not bound input already allocated by the caller. Some native operations also allocate before they can check a limit: CSV may parse one record, ZIP may read the central directory, and logging may construct a full record. Bound source reads and consult each package's behavior section.

| Facility | Native limit |
| --- | --- |
| JSON | Supplied depth budgets are respected; cycles cannot be serialized. |
| HTTP | Header limits are optional; the native reader remains constrained by integer representability. |
| Allocated lists | `filled` and `range` return `LimitExceeded` beyond 2^28 items, even with a larger `max_items`. |
| Allocated strings | `repeat`, `pad_start` and `pad_end` return `LimitExceeded` beyond 1 GiB, even with a larger `max_bytes`. |
| Entropy | 16 MiB per call. |
| UDP receive | At most 65535 bytes. |

These limits do not form a general memory or CPU sandbox.

## Cancellation and partial effects

Native loops check cancellation between bounded chunks. A single math, regex, big-integer, directory, resolver, or OS call may delay cancellation until it returns. There is no forced termination.

Writing, copying, or removing data can fail after changing an external prefix. Cancellation and errors do not imply rollback or a transaction.

## Access to external services

Imported host accessors supply filesystem, entropy, wall-clock, system, network, and command services. Source fakes implement the same contracts with explicit contract views.

Pure codec, path, math, and hash functions grant no OS access. Native CLI services use the process's OS permissions. Filesystem subtree restrictions are not implemented; `Network.restrict` narrows destination access. Imported host accessors obtain services from the current execution. HTTP and socket operations retain their service interfaces and TLS verification.

Networking includes DNS, Unix sockets, verified TLS, streaming HTTP, and WebSockets. HTTP/3 is outside the supported scope. Native builds bundle pinned dependency sources and licenses rather than fetching packages.
