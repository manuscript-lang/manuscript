# A value built and inspected through its module's operations.
export opaque type Sealed[T]:
    # An implementation detail absent from the public API.
    secret_value: T

impl Sealed[T]:
    # Reports the supplied flag, which defaults to true.
    fn accepts(flag: Bool = true) Bool:
        return flag

interface OrderedSealed[T: Comparable]:
    fn precedes(other: T) Bool

impl OrderedSealed[T] for Sealed[T]:
    # Compares the stored value with the argument.
    fn precedes(other: T) Bool:
        return self.secret_value.compare(other) < 0

# A value whose cases remain local to this module.
export opaque type Token:
    # A private nullary constructor.
    case Minted
    # A private constructor with a payload.
    case Labeled(secret_payload: String)

impl Token:
    # Reports whether this is a token issued by the module.
    fn valid() Bool:
        return true

# An ordinary record with a public constructor and field.
export type Plain:
    # A visible value with an explicit default.
    visible: Int = 3

# An ordinary alternative with public cases and payloads.
export type Choice:
    # A case with no payload.
    case Vacant
    # A case carrying a public integer.
    case Filled(payload: Int)
