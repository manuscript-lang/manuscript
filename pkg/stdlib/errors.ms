# Expected failures share this explicitly implemented diagnostic contract.

# A contract for expected failures that can provide a human-readable message.
export interface Error:
    # Returns a human-readable description of this expected error.
    fn message() -> String

# An error that carries only intentional text, for callers that have no domain error to return.
export type TextError:
    # Wraps the human-readable description returned by message().
    case Text(
        # Description returned verbatim by message().
        message: String
    )

impl Error for TextError:
    # Returns the wrapped text verbatim.
    fn message() -> String:

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
export fn category(cause: Error) -> Optional[ErrorCategory]:
