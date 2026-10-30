import Data from "@std/core.ms"

# An immutable sequence of bytes. Indices and slice bounds are zero-based.
export type Bytes: ...

impl Data for Bytes:

impl Bytes:
    # Copies byte storage without changing the receiver.
    fn clone() Bytes: ...

    # Tests whether `value` occurs as a byte subsequence.
    fn contains(value: Bytes) Bool: ...

    # Splits exact byte separators into a fresh list of immutable byte views.
    # Nonempty separators retain empty parts; empty data then yields one empty Bytes.
    # Omitted/none max_parts is unlimited; zero returns no parts, negatives fault.
    # A cap truncates parts; empty separator yields one Bytes per byte, no parts for empty data.
    fn split(separator: Bytes, max_parts: Int? = none) List[Bytes]: ...

    # Selects [start, end) in bytes; negative bounds are relative to the end.
    # Bounds outside 0 <= start <= end <= length() return CollectionError.OutOfRange.
    # The immutable result may share storage with the receiver.
    fn slice(start: Int, end: Int) Result[Bytes, CollectionError]: ...

    # Returns an unsigned byte; negative indexes are relative to the end. An out-of-range index returns `default`, and without one raises a fault.
    fn get(index: Int, default: UInt8? = none) UInt8: ...

    # Returns the first matching byte offset or `none`; empty `value` matches at zero.
    fn index_of(value: Bytes) Int?: ...

    # Returns the first offset at or after `start` holding the byte `value`, or `none`.
    # A `start` past length() gives `none`; a negative `start` counts as zero.
    fn index_of_byte(value: UInt8, start: Int) Int?: ...

    # Returns the last matching byte offset or `none`; empty `value` matches at length().
    fn last_index_of(value: Bytes) Int?: ...

    # Tests whether the receiver begins with these bytes.
    fn starts_with(prefix: Bytes) Bool: ...

    # Tests whether the receiver ends with these bytes.
    fn ends_with(suffix: Bytes) Bool: ...

    # Returns a reversed copy without changing the receiver.
    fn reversed() Bytes: ...

    # Returns a copy with one byte replaced; negative indexes are relative to the end.
    # An out-of-range index faults.
    fn with_value(index: Int, value: UInt8) Bytes: ...

    # Tests whether the receiver contains no bytes.
    fn is_empty() Bool: ...

    # Returns a fresh mutable list of unsigned byte values; changing it leaves the Bytes unchanged.
    fn values() List[UInt8]: ...

    # Returns concatenated bytes without changing either operand.
    fn concat(other: Bytes) Bytes: ...

    # Returns the number of bytes, not the number of Unicode characters.
    fn length() Int: ...

    # Decodes valid UTF-8 as text, or returns `none` when the bytes are invalid.
    fn decode_utf8() String?: ...

    # Decodes [start, end) as `decode_utf8` does, without copying the range into a new Bytes first.
    # Bounds outside 0 <= start <= end <= length() raise a fault.
    fn decode_utf8_range(start: Int, end: Int) String?: ...

# Returns the parts end to end as one new Bytes; an empty list gives empty bytes. One allocation and one copy of each part, unlike repeated concat.
export fn join(parts: List[Bytes]) Bytes: ...

# Returns a fresh mutable list of bytes, like data.values().
export fn values(data: Bytes) List[UInt8]: ...

# Builds a byte sequence efficiently before freezing it into an immutable value.
export type BytesBuilder: ...

impl BytesBuilder:
    # Appends one byte to the end of the builder.
    var fn append(value: UInt8) Unit: ...

    # Appends all supplied bytes in order; the input is unchanged.
    var fn append_bytes(values: Bytes) Unit: ...

    # Consumes the builder and returns its bytes; the builder cannot be used afterwards.
    fn build() Bytes: ...

    # Returns the bytes appended so far and leaves the builder empty, for a builder held in a field.
    var fn drain() Bytes: ...

# Returned when a fixed-width read crosses the end of the bytes.
export type BinaryError:
    # The read starts before the buffer or needs bytes past its end.
    case OutOfRange

impl Error for BinaryError:
    # Returns a binary-prefixed diagnostic without echoing source bytes or numeric input.
    fn message() String: ...

# Fixed-width number codecs for Bytes and BytesBuilder, written in Manuscript over one word reader and four float bit casts.
# They apply wherever Bytes and BytesBuilder are used, without an import.
# The `width` bytes at `at` (1, 2, 4 or 8) as an unsigned number; eight bytes keep their bit pattern as an Int.
extern fn msrt_bytes_read_word(
    data: Bytes,
    at: Int,
    width: Int,
    little: Bool
) Result[Int, BinaryError]

extern fn msrt_float_from_bits(bits: Int) Float

extern fn msrt_float_to_bits(value: Float) Int

extern fn msrt_float32_from_bits(bits: Int) Float

extern fn msrt_float32_to_bits(value: Float) Int

extern fn msrt_bits_bit_and(left: Int, right: Int) Int

extern fn msrt_bits_shift_right(value: Int, count: Int) Int

# Appends the low `width` bytes of `value` in the requested byte order.
fn put_word(var out: BytesBuilder, value: Int, width: Int, little: Bool) Unit:
    for i in 0..width:
        var place = width - 1 - i
        if little:
            place = i
        out.append(
            msrt_bits_bit_and(
                msrt_bits_shift_right(value, 8 * place), 255
            ).to_uint8().get(0)
        )

# Reads a signed value from its unsigned bit pattern: `half` is 2 to the power `bits - 1`.
fn signed(raw: Int, half: Int) Int:
    if raw >= half:
        return raw - half * 2

    return raw

interface BytesCodecs:
    fn int8(at: Int) Result[Int8, BinaryError]
    fn uint8(at: Int) Result[UInt8, BinaryError]
    fn int16_le(at: Int) Result[Int16, BinaryError]
    fn uint16_le(at: Int) Result[UInt16, BinaryError]
    fn int16_be(at: Int) Result[Int16, BinaryError]
    fn uint16_be(at: Int) Result[UInt16, BinaryError]
    fn int32_le(at: Int) Result[Int32, BinaryError]
    fn uint32_le(at: Int) Result[UInt32, BinaryError]
    fn int32_be(at: Int) Result[Int32, BinaryError]
    fn uint32_be(at: Int) Result[UInt32, BinaryError]
    fn int64_le(at: Int) Result[Int, BinaryError]
    fn int64_be(at: Int) Result[Int, BinaryError]
    fn float32_le(at: Int) Result[Float32, BinaryError]
    fn float32_be(at: Int) Result[Float32, BinaryError]
    fn float64_le(at: Int) Result[Float, BinaryError]
    fn float64_be(at: Int) Result[Float, BinaryError]

impl BytesCodecs for Bytes:
    # Reads one signed byte at `at`; a missing byte returns BinaryError.OutOfRange. Offsets are absolute, so a negative `at` is out of range.
    fn int8(at: Int) Result[Int8, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 1, true)
        return ok(signed(raw, 128).to_int8().get(0))

    # Reads one unsigned byte at `at`.
    fn uint8(at: Int) Result[UInt8, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 1, true)
        return ok(raw.to_uint8().get(0))

    # Reads a signed 16-bit little-endian integer from two bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn int16_le(at: Int) Result[Int16, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 2, true)
        return ok(signed(raw, 32768).to_int16().get(0))

    # Reads an unsigned 16-bit little-endian integer from two bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn uint16_le(at: Int) Result[UInt16, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 2, true)
        return ok(raw.to_uint16().get(0))

    # Reads a signed 16-bit big-endian integer from two bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn int16_be(at: Int) Result[Int16, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 2, false)
        return ok(signed(raw, 32768).to_int16().get(0))

    # Reads an unsigned 16-bit big-endian integer from two bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn uint16_be(at: Int) Result[UInt16, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 2, false)
        return ok(raw.to_uint16().get(0))

    # Reads a signed 32-bit little-endian integer from four bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn int32_le(at: Int) Result[Int32, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 4, true)
        return ok(signed(raw, 2147483648).to_int32().get(0))

    # Reads an unsigned 32-bit little-endian integer from four bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn uint32_le(at: Int) Result[UInt32, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 4, true)
        return ok(raw.to_uint32().get(0))

    # Reads a signed 32-bit big-endian integer from four bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn int32_be(at: Int) Result[Int32, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 4, false)
        return ok(signed(raw, 2147483648).to_int32().get(0))

    # Reads an unsigned 32-bit big-endian integer from four bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn uint32_be(at: Int) Result[UInt32, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 4, false)
        return ok(raw.to_uint32().get(0))

    # Reads a signed 64-bit little-endian integer from eight bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn int64_le(at: Int) Result[Int, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 8, true)
        return ok(raw)

    # Reads a signed 64-bit big-endian integer from eight bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn int64_be(at: Int) Result[Int, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 8, false)
        return ok(raw)

    # Reads an IEEE 754 binary32 little-endian float from four bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn float32_le(at: Int) Result[Float32, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 4, true)
        return ok(msrt_float32_from_bits(raw).to_float32().get(0.0))

    # Reads an IEEE 754 binary32 big-endian float from four bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn float32_be(at: Int) Result[Float32, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 4, false)
        return ok(msrt_float32_from_bits(raw).to_float32().get(0.0))

    # Reads an IEEE 754 binary64 little-endian float from eight bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn float64_le(at: Int) Result[Float, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 8, true)
        return ok(msrt_float_from_bits(raw))

    # Reads an IEEE 754 binary64 big-endian float from eight bytes at `at`; missing bytes return BinaryError.OutOfRange.
    fn float64_be(at: Int) Result[Float, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 8, false)
        return ok(msrt_float_from_bits(raw))

interface BytesBuilderCodecs:
    var fn append_int8(value: Int8) Unit
    var fn append_int16_le(value: Int16) Unit
    var fn append_uint16_le(value: UInt16) Unit
    var fn append_int16_be(value: Int16) Unit
    var fn append_uint16_be(value: UInt16) Unit
    var fn append_int32_le(value: Int32) Unit
    var fn append_uint32_le(value: UInt32) Unit
    var fn append_int32_be(value: Int32) Unit
    var fn append_uint32_be(value: UInt32) Unit
    var fn append_int64_le(value: Int) Unit
    var fn append_int64_be(value: Int) Unit
    var fn append_float32_le(value: Float32) Unit
    var fn append_float32_be(value: Float32) Unit
    var fn append_float64_le(value: Float) Unit
    var fn append_float64_be(value: Float) Unit

impl BytesBuilderCodecs for BytesBuilder:
    # Appends one signed byte.
    var fn append_int8(value: Int8) Unit:
        put_word(var self, value.to_int(), 1, true)

    # Appends a signed 16-bit little-endian integer.
    var fn append_int16_le(value: Int16) Unit:
        put_word(var self, value.to_int(), 2, true)

    # Appends an unsigned 16-bit little-endian integer.
    var fn append_uint16_le(value: UInt16) Unit:
        put_word(var self, value.to_int(), 2, true)

    # Appends a signed 16-bit big-endian integer.
    var fn append_int16_be(value: Int16) Unit:
        put_word(var self, value.to_int(), 2, false)

    # Appends an unsigned 16-bit big-endian integer.
    var fn append_uint16_be(value: UInt16) Unit:
        put_word(var self, value.to_int(), 2, false)

    # Appends a signed 32-bit little-endian integer.
    var fn append_int32_le(value: Int32) Unit:
        put_word(var self, value.to_int(), 4, true)

    # Appends an unsigned 32-bit little-endian integer.
    var fn append_uint32_le(value: UInt32) Unit:
        put_word(var self, value.to_int(), 4, true)

    # Appends a signed 32-bit big-endian integer.
    var fn append_int32_be(value: Int32) Unit:
        put_word(var self, value.to_int(), 4, false)

    # Appends an unsigned 32-bit big-endian integer.
    var fn append_uint32_be(value: UInt32) Unit:
        put_word(var self, value.to_int(), 4, false)

    # Appends a signed 64-bit little-endian integer.
    var fn append_int64_le(value: Int) Unit:
        put_word(var self, value, 8, true)

    # Appends a signed 64-bit big-endian integer.
    var fn append_int64_be(value: Int) Unit:
        put_word(var self, value, 8, false)

    # Appends an IEEE 754 binary32 little-endian float.
    var fn append_float32_le(value: Float32) Unit:
        put_word(var self, msrt_float32_to_bits(value.to_float()), 4, true)

    # Appends an IEEE 754 binary32 big-endian float.
    var fn append_float32_be(value: Float32) Unit:
        put_word(var self, msrt_float32_to_bits(value.to_float()), 4, false)

    # Appends an IEEE 754 binary64 little-endian float.
    var fn append_float64_le(value: Float) Unit:
        put_word(var self, msrt_float_to_bits(value), 8, true)

    # Appends an IEEE 754 binary64 big-endian float.
    var fn append_float64_be(value: Float) Unit:
        put_word(var self, msrt_float_to_bits(value), 8, false)
