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

# Returns the parts end to end as one new Bytes; an empty list gives empty bytes. One allocation and one copy of each part, unlike repeated concat.
export def join(parts: List[Bytes]) -> Bytes: ...

# Returns a fresh mutable list of byte values in the range 0 through 255, like data.values().
export def values(data: Bytes) -> List[Int]: ...

# Builds a byte sequence efficiently before freezing it into an immutable value.
export type BytesBuilder: ...

impl BytesBuilder:
    # Appends one unsigned byte; values outside 0 through 255 or writes after build fault.
    def append(value: Int) -> Unit: ...

    # Appends all supplied bytes in order; the input is unchanged, and a sealed builder faults.
    def append_bytes(values: Bytes) -> Unit: ...

    # Seals the builder and returns its immutable bytes; repeated build returns the same value.
    def build() -> Bytes: ...

# Returned when a fixed-width read crosses the end of the bytes.
export type BinaryError:
    # The read starts before the buffer or needs bytes past its end.
    case OutOfRange

impl Error for BinaryError:
    # Returns a binary-prefixed diagnostic without echoing source bytes or numeric input.
    def message() -> String: ...
