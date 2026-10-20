# Represents a value that may be absent: `some(value)` or `none`.
export type Optional[T]:
    # A present payload, retained by reference when T is mutable.
    case some(
        # The contained value; unwrap and matching return this original payload.
        value: T
    )
    # An absent value with no payload; no T needs to be constructed.
    case none

impl Optional[T]:
    # Returns true for some(value), and false for none.
    fn is_some() Bool:

    # Reports whether this value is absent.
    fn is_none() Bool:

    # Returns the payload, or `default` when this is `none`. Without a default, `none` raises a fault.
    fn get(default: Optional[T] = none) T:

    # Transforms a present payload; none remains absent.
    fn map[U](transform: fn(value: T) U) Optional[U]:

    # Calls transform only when present, returning its Optional unchanged.
    fn and_then[U](transform: fn(value: T) Optional[U]) Optional[U]:

    # Calls create once only when absent, returning its Optional unchanged.
    fn or_else(create: fn() Optional[T]) Optional[T]:

    # Returns ok with the original payload, or error with the eager cause.
    # Without a cause, E is MissingValue and the error names the calling source file and line.
    fn ok_or[E: Error = MissingValue](cause: Optional[E] = none) Result[T, E]:

    # Constructs an error once only for none; present payloads remain unchanged.
    fn ok_or_else[E: Error](create: fn() E) Result[T, E]:
