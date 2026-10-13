# Canonical standard-library declarations. Implementations are native.

# Holds either a successful value (`ok`) or an expected failure (`error`).
export type Result[T, E]:
    case ok(value: T)
    case error(cause: E)
    # Reports whether this result contains a successful value.
    fn is_ok() -> Bool:
    # Reports whether this result contains an expected error.
    fn is_error() -> Bool:
    # Returns the successful payload; faults when this is an error.
    fn unwrap() -> T:
    # Returns the error payload; faults when this is successful.
    fn unwrap_error() -> E:
    # Returns the successful payload, or the eagerly evaluated fallback.
    fn unwrap_or(fallback: T) -> T:
    # Calls create once with the original error only when this is an error.
    fn unwrap_or_else(create: fn(cause: E) -> T) -> T:
    # Transforms only a successful payload, preserving an error unchanged.
    fn map[U](transform: fn(value: T) -> U) -> Result[U, E]:
    # Calls transform only on success. Its result keeps the same error type.
    fn and_then[U](transform: fn(value: T) -> Result[U, E]) -> Result[U, E]:
