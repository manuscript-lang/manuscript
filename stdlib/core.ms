# Expected failures share this explicitly implemented diagnostic contract.
# A contract for expected failures that can provide a human-readable message.
export interface Error:
    # Returns a human-readable description of this expected error.
    fn message() String

# An error that carries only intentional text, for callers that have no domain error to return.
export type TextError:
    # Description returned verbatim by message().
    text: String

impl Error for TextError:
    # Returns the wrapped text verbatim.
    fn message() String: ...

# The error `Optional.ok_or()` returns when no cause is given. Its message names the source file and line of the call.
export type MissingValue:
    # Records where the absent value was converted to an error.
    case Missing(
        # The calling source position, as `file:line`.
        location: String
    )

impl Error for MissingValue:
    # Returns "missing value at" followed by the recorded source position.
    fn message() String: ...

# Portable categories for shared standard error cases. Domain errors retain their types and payloads.
export type ErrorCategory:
    # Caller input is invalid.
    case InvalidInput
    # Input data is malformed.
    case InvalidData
    # An operation budget or implementation limit was exceeded.
    case LimitExceeded
    # A requested resource was not found.
    case NotFound
    # A requested exclusive resource already exists.
    case AlreadyExists
    # Host authority denied the operation.
    case PermissionDenied
    # The requested operation is unsupported.
    case Unsupported
    # The resource has been closed.
    case Closed
    # A local operation or group deadline expired.
    case Timeout
    # The service/resource is unavailable; this does not imply NotFound or PermissionDenied.
    case Unavailable

# Queries a shared category without changing or invoking the error.
# Recognized standard cases use their same-name category.
# Custom errors and domain-specific cases (including Failed, Full, OutputLimit, OutOfRange,
# AuthenticationFailed and wrapped LogError causes) return none. Messages are never parsed.
export fn category(cause: Error) ErrorCategory?: ...

# Raises a programming fault with the supplied message and stops the current operation.
export fn panic(message: String) Never: ...

# A resource that can be closed. A binding that holds one is closed when its scope ends, on every exit.
export interface Closeable:
    # Releases the implementation's resource state; with calls this on every scope exit.
    # Cleanup runs during return, expected errors, faults, and cancellation too.
    var fn close() Unit

# A resource whose release can fail. A binding that holds one is closed when its scope ends, as with
# `Closeable`, but a failed close is returned: the implicit close behaves like `try value.close()`, so the
# enclosing function must return `Result[_, Error]`. When the scope already ends in an error, that error
# is returned and the close error is dropped. Call `close()` yourself to handle a failure.
export interface FallibleCloseable:
    # Releases the resource, returning the failure if it could not be released cleanly.
    var fn close() Result[Unit, Error]

# A source of items that `for` walks: each `next` returns the following item, or `none` once exhausted.
# `for item in source:` calls `next` until `none`; a variable or field path advances in place and
# keeps its final state, while any other expression is held by the loop alone. `next` should keep
# returning `none` after the end. The item is a borrow: it stays valid, and the iterator
# unchanged, until the loop body ends; clone it to keep it.
export interface Iterator[T]:
    # Returns the next item, or none when no items remain. The item borrows from the iterator
    # (an iterator over a container borrows from the container instead).
    var fn next() ref T?

# Represents a value that may be absent: a `T` or `none`; a plain `T` converts where a `T?` is expected.
export type Optional[T]:
    # A present payload, retained by reference when T is mutable.
    case some(
        # The contained value; unwrap and matching return this original payload.
        value: T
    )
    # An absent value with no payload; no T needs to be constructed.
    case none

impl T?:
    # Returns True when a value is present, and False for none.
    fn is_some() Bool: ...

    # Reports whether this value is absent.
    fn is_none() Bool: ...

    # Returns the payload, or `default` when this is `none`; pass a default or unwrap with `if let value = optional:` unless absence is a bug.
    # Without a default, `none` raises a fault.
    fn get(default: T?) ref T: ...

    # Transforms a present payload; none remains absent.
    fn map[U](transform: fn(T) U) U?: ...

    # Calls transform only when present, returning its Optional unchanged.
    fn and_then[U](transform: fn(T) U?) U?: ...

    # Returns the payload, or calls create once and returns its value only when absent.
    fn get_or_else(create: fn() T) T: ...

    # Calls create once only when absent, returning its Optional unchanged.
    fn or_else(create: fn() T?) T?: ...

    # Returns ok with the original payload, or error with the eager cause.
    # Without a cause, E is MissingValue and the error names the calling source file and line.
    fn ok_or[E: Error = MissingValue](cause: E?) Result[T, E]: ...

    # Constructs an error once only for none; present payloads remain unchanged.
    fn ok_or_else[E: Error](create: fn() E) Result[T, E]: ...

# Holds either a successful value (`ok`) or an expected failure (`error`).
export type Result[T, E: Error]:
    # A successful result, retaining its payload without a deep copy.
    case ok(
        # The successful value returned by unwrap, matching, or propagation.
        value: T
    )
    # An expected failure value; it is distinct from faults and cancellation.
    case error(
        # The original domain error, retained through compatible Result propagation.
        cause: E
    )

impl Result[T, E]:
    # Reports whether this result contains a successful value.
    fn is_ok() Bool: ...

    # Reports whether this result contains an expected error.
    fn is_error() Bool: ...

    # Returns the successful payload, or `default` when this is an error; pass a default or propagate with `try` unless failure is a bug.
    # Without a default, an error raises a fault.
    fn get(default: T?) ref T: ...

    # Returns the error payload; check `is_error()` first, because a successful result raises a fault.
    fn err() ref E: ...

    # Returns the successful payload, or calls create once with the original error and returns its value.
    fn get_or_else(create: fn(E) T) T: ...

    # Calls create once with the original error only when this is an error, returning its Result.
    fn or_else(create: fn(E) Result[T, E]) Result[T, E]: ...

    # Transforms only an error, preserving a successful payload unchanged.
    fn map_error[F: Error](transform: fn(E) F) Result[T, F]: ...

    # Transforms only a successful payload, preserving an error unchanged.
    fn map[U](transform: fn(T) U) Result[U, E]: ...

    # Calls transform only on success. Its result keeps the same error type.
    fn and_then[U](transform: fn(T) Result[U, E]) Result[U, E]: ...

    # Returns some with the original success payload, or none for an error.
    fn to_optional() T?: ...

# Equality and hashing are ordinary operation interfaces. Built-in data retains
# its value semantics; an explicit implementation selects domain identity.
export interface Equal:
    # Compares this value with another value of the same type.
    fn equals(other: Self) Bool

# A type with a total order; `compare` agrees with `equals` when both are implemented.
export interface Comparable:
    # Orders this value against another of the same type: negative when it sorts before, zero when neither sorts first, positive when it sorts after.
    fn compare(other: Self) Int

# A type whose values can be duplicated. Plain data is Clonable; functions, interface values and resource handles are not.
# There is nothing to implement: the bound `T: Clonable` makes `value.clone()` available on a type parameter.
export interface Clonable:
    # Returns an independent deep copy of this value.
    fn clone() Self

# A type whose values are plain data: no resource, function, interface value, or runtime handle
# anywhere inside. Bytes cross a boundary only as data, so `json.parse`, `json.stringify`, and the
# message types of processes, workers, tasks and channels require `T: Data`.
# There is nothing to implement. Records and alternatives are `Data` when every field is; among the collections
# only `List` is, when its element is. A `Map` or `Set` is never `Data`, nor is a `Closeable` type or an `opaque type`; `JsonValue`
# is `Data` by declaration, so a JSON object travels as a `JsonValue`.
export interface Data: ...

# A type whose values are plain words in the runtime, so passing one duplicates it with a bit copy and
# the original stays usable. Only an extern type in the standard library declares it, with `impl Copy for T:`;
# records and alternatives are copied when every field is, and every other native moves.
export interface Copy: ...

# A type with a stable hash consistent with its `Equal` implementation.
export interface Hashable:
    # Returns a stable hash consistent with `equals` for the same value.
    fn hash() Int
