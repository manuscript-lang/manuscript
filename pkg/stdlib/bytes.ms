# Canonical standard-library declarations. Implementations are native.

# An immutable sequence of bytes. Indices and slice bounds are zero-based.
export type Bytes:
    # Copies byte storage without changing the receiver.
    fn clone() -> Bytes:
    # Tests whether `value` occurs as a byte subsequence.
    fn contains(value: Bytes) -> Bool:
    # Splits exact byte separators into a fresh list of immutable byte views.
    # Nonempty separators retain empty parts; empty data then yields one empty Bytes.
    # Omitted/none max_parts is unlimited; zero returns no parts, negatives fault.
    # A cap truncates parts; empty separator yields one Bytes per byte, no parts for empty data.
    fn split(separator: Bytes, max_parts: Optional[Int] = none) -> List[Bytes]:
    # Selects [start, end) in bytes; negative bounds are relative to the end.
    # Bounds outside 0 <= start <= end <= length() return CollectionError.OutOfRange.
    # The immutable result may share storage with the receiver.
    fn slice(start: Int, end: Int) -> Result[Bytes, CollectionError]:
    # Returns an unsigned byte; negative indexes are relative to the end, and out-of-range indexes return `none`.
    fn at(index: Int) -> Optional[Int]:
    # Returns the first matching byte offset or `none`; empty `value` matches at zero.
    fn index_of(value: Bytes) -> Optional[Int]:
    # Returns the last matching byte offset or `none`; empty `value` matches at length().
    fn last_index_of(value: Bytes) -> Optional[Int]:
    # Tests whether the receiver begins with these bytes.
    fn starts_with(prefix: Bytes) -> Bool:
    # Tests whether the receiver ends with these bytes.
    fn ends_with(suffix: Bytes) -> Bool:
    # Returns a reversed copy without changing the receiver.
    fn reversed() -> Bytes:
    # Returns a copy with one byte replaced; negative indexes are relative to the end.
    # An out-of-range index or a value outside 0 through 255 faults.
    fn with_value(index: Int, value: Int) -> Bytes:
    # Tests whether the receiver contains no bytes.
    fn is_empty() -> Bool:
    # Returns a fresh mutable list of unsigned byte values; changing it leaves the Bytes unchanged.
    fn values() -> List[Int]:
    # Returns concatenated bytes without changing either operand.
    fn concat(other: Bytes) -> Bytes:
    # Returns the number of bytes, not the number of Unicode characters.
    fn length() -> Int:
    # Decodes valid UTF-8 as text, or returns `none` when the bytes are invalid.
    fn to_string() -> Optional[String]:

# Returns a fresh mutable list of byte values in the range 0 through 255, like data.values().
export fn values(data: Bytes) -> List[Int]:

# Builds a byte sequence efficiently before freezing it into an immutable value.
export type BytesBuilder:
    # Appends one unsigned byte; values outside 0 through 255 or writes after freeze fault.
    fn append(value: Int) -> Unit:
    # Appends all supplied bytes in order; the input is unchanged, and a sealed builder faults.
    fn concat(values: Bytes) -> Unit:
    # Seals the builder and returns its immutable bytes; repeated freeze returns the same value.
    fn freeze() -> Bytes:
