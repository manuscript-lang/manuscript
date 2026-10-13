# Canonical standard-library declarations. Implementations are native.

# Represents a value that may be absent: `some(value)` or `none`.
export type Optional[T]:
    case some(value: T)
    case none
    # Reports whether this value contains a payload.
    fn is_some() -> Bool:
    # Reports whether this value is absent.
    fn is_none() -> Bool:
    # Returns the payload. Calling this on `none` raises a fault.
    fn unwrap() -> T:
    # Returns the contained value, or `fallback` when this is `none`.
    fn unwrap_or(fallback: T) -> T:
    # Computes a fallback only when this is `none`.
    fn unwrap_or_else(create: fn() -> T) -> T:
