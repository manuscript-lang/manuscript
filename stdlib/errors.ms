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
    fn message() String:

# The error `Optional.ok_or()` returns when no cause is given. Its message names the source file and line of the call.
export type MissingValue:
    # Records where the absent value was converted to an error.
    case Missing(
        # The calling source position, as `file:line`.
        location: String
    )

impl Error for MissingValue:
    # Returns "missing value at" followed by the recorded source position.
    fn message() String:

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
export fn category(cause: Error) Optional[ErrorCategory]:
