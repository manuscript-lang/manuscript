# An immutable sequence of bytes. Indices and slice bounds are zero-based.
export type Bytes: ...

impl Bytes:
    # Copies byte storage without changing the receiver.
    def clone() -> Bytes: ...

    # Tests whether `value` occurs as a byte subsequence.
    def contains(value: Bytes) -> Bool: ...

    # Splits exact byte separators into a fresh list of immutable byte views.
    # Nonempty separators retain empty parts; empty data then yields one empty Bytes.
    # Omitted/none max_parts is unlimited; zero returns no parts, negatives fault.
    # A cap truncates parts; empty separator yields one Bytes per byte, no parts for empty data.
    def split(separator: Bytes, max_parts: Optional[Int] = none) -> List[Bytes]: ...

    # Selects [start, end) in bytes; negative bounds are relative to the end.
    # Bounds outside 0 <= start <= end <= length() return CollectionError.OutOfRange.
    # The immutable result may share storage with the receiver.
    def slice(start: Int, end: Int) -> Result[Bytes, CollectionError]: ...

    # Returns an unsigned byte; negative indexes are relative to the end. An out-of-range index returns `default`, and without one raises a fault.
    def get(index: Int, default: Optional[Int] = none) -> Int: ...

    # Returns the first matching byte offset or `none`; empty `value` matches at zero.
    def index_of(value: Bytes) -> Optional[Int]: ...

    # Returns the last matching byte offset or `none`; empty `value` matches at length().
    def last_index_of(value: Bytes) -> Optional[Int]: ...

    # Tests whether the receiver begins with these bytes.
    def starts_with(prefix: Bytes) -> Bool: ...

    # Tests whether the receiver ends with these bytes.
    def ends_with(suffix: Bytes) -> Bool: ...

    # Returns a reversed copy without changing the receiver.
    def reversed() -> Bytes: ...

    # Returns a copy with one byte replaced; negative indexes are relative to the end.
    # An out-of-range index or a value outside 0 through 255 faults.
    def with_value(index: Int, value: Int) -> Bytes: ...

    # Tests whether the receiver contains no bytes.
    def is_empty() -> Bool: ...

    # Returns a fresh mutable list of unsigned byte values; changing it leaves the Bytes unchanged.
    def values() -> List[Int]: ...

    # Returns concatenated bytes without changing either operand.
    def concat(other: Bytes) -> Bytes: ...

    # Returns the number of bytes, not the number of Unicode characters.
    def length() -> Int: ...

    # Decodes valid UTF-8 as text, or returns `none` when the bytes are invalid.
    def decode_utf8() -> Optional[String]: ...

# Returns a fresh mutable list of byte values in the range 0 through 255, like data.values().
export def values(data: Bytes) -> List[Int]: ...

# Builds a byte sequence efficiently before freezing it into an immutable value.
export type BytesBuilder: ...

impl BytesBuilder:
    # Appends one unsigned byte; values outside 0 through 255 or writes after freeze fault.
    def append(value: Int) -> Unit: ...

    # Appends all supplied bytes in order; the input is unchanged, and a sealed builder faults.
    def concat(values: Bytes) -> Unit: ...

    # Seals the builder and returns its immutable bytes; repeated freeze returns the same value.
    def freeze() -> Bytes: ...

# Errors returned when a byte range or numeric representation is invalid.
export type BinaryError:
    # Integer width is unsupported; the native codec accepts only 1, 2, 4 or 8 bytes.
    case InvalidInput
    # A read crosses the byte buffer or a number cannot fit the requested signedness/width or result type.
    case OutOfRange

# Reads a 64-bit floating-point value (binary64, 8 bytes) at `offset` using the selected byte order.
export def read_float(
    data: Bytes,
    offset: Int,
    little_endian: Bool
) -> Result[Float, BinaryError]: ...

# Reads an integer of `width` bytes. Signed values use two's-complement encoding.
export def read_integer(
    data: Bytes,
    offset: Int,
    width: Int,
    signed: Bool,
    little_endian: Bool
) -> Result[Int, BinaryError]: ...

# Encodes a 64-bit floating-point value (binary64) as 8 bytes using the selected byte order.
export def write_float(value: Float, little_endian: Bool) -> Bytes: ...

# Encodes an integer into `width` bytes, returning an error when it does not fit.
export def write_integer(
    value: Int,
    width: Int,
    signed: Bool,
    little_endian: Bool
) -> Result[Bytes, BinaryError]: ...

impl Error for BinaryError:
    # Returns a binary-prefixed diagnostic without echoing source bytes or numeric input.
    def message() -> String: ...
