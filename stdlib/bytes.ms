from "@std/bytes.ms" import Bytes, BytesBuilder, BinaryError
from "@std/collections.ms" import range
from "@std/core.ms" import panic

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

# Fixed-width number codecs for Bytes and BytesBuilder, written in Manuscript over one word reader and four float bit casts.
# They apply wherever Bytes and BytesBuilder are used, without an import.
# The `width` bytes at `at` (1, 2, 4 or 8) as an unsigned number; eight bytes keep their bit pattern as an Int.
extern def msrt_bytes_read_word(
    data: Bytes,
    at: Int,
    width: Int,
    little: Bool
) -> Result[Int, BinaryError]

extern def msrt_float_from_bits(bits: Int) -> Float

extern def msrt_float_to_bits(value: Float) -> Int

extern def msrt_float32_from_bits(bits: Int) -> Float

extern def msrt_float32_to_bits(value: Float) -> Int

extern def msrt_bits_bit_and(left: Int, right: Int) -> Int

extern def msrt_bits_shift_right(value: Int, count: Int) -> Int

# Appends the low `width` bytes of `value` in the requested byte order.
def put_word(var out: BytesBuilder, value: Int, width: Int, little: Bool) -> Unit:
    for i in range(0, width):
        var place = width - 1 - i
        if little:
            place = i
        out.append(msrt_bits_bit_and(msrt_bits_shift_right(value, 8 * place), 255))

# Appends an unsigned `value` after checking that it is below `limit`, which is 2 to the power `bits`.
def put_unsigned(
    var out: BytesBuilder, value: Int, limit: Int, width: Int, little: Bool,
    name: String
) -> Unit:
    if value < 0 or value >= limit:
        panic(
            f"BytesBuilder.{name}: value {value} does not fit {width * 8} unsigned bits"
        )
    put_word(var out, value, width, little)

# Reads a signed value from its unsigned bit pattern: `half` is 2 to the power `bits - 1`.
def signed(raw: Int, half: Int) -> Int:
    if raw >= half:
        return raw - half * 2

    return raw

interface BytesCodecs:
    def int8(at: Int) -> Result[Int8, BinaryError]
    def uint8(at: Int) -> Result[Int, BinaryError]
    def int16_le(at: Int) -> Result[Int16, BinaryError]
    def uint16_le(at: Int) -> Result[Int, BinaryError]
    def int16_be(at: Int) -> Result[Int16, BinaryError]
    def uint16_be(at: Int) -> Result[Int, BinaryError]
    def int32_le(at: Int) -> Result[Int32, BinaryError]
    def uint32_le(at: Int) -> Result[Int, BinaryError]
    def int32_be(at: Int) -> Result[Int32, BinaryError]
    def uint32_be(at: Int) -> Result[Int, BinaryError]
    def int64_le(at: Int) -> Result[Int, BinaryError]
    def int64_be(at: Int) -> Result[Int, BinaryError]
    def float32_le(at: Int) -> Result[Float32, BinaryError]
    def float32_be(at: Int) -> Result[Float32, BinaryError]
    def float64_le(at: Int) -> Result[Float, BinaryError]
    def float64_be(at: Int) -> Result[Float, BinaryError]

impl BytesCodecs for Bytes:
    # Reads one signed byte at `at`; a missing byte returns BinaryError.OutOfRange. Offsets are absolute, so a negative `at` is out of range.
    def int8(at: Int) -> Result[Int8, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 1, True)
        return ok(signed(raw, 128).to_int8().get(0))

    # Reads one unsigned byte at `at` as an Int (0 through 255).
    def uint8(at: Int) -> Result[Int, BinaryError]:
        return msrt_bytes_read_word(self, at, 1, True)

    # Reads a signed 16-bit little-endian integer from two bytes at `at`; missing bytes return BinaryError.OutOfRange.
    def int16_le(at: Int) -> Result[Int16, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 2, True)
        return ok(signed(raw, 32768).to_int16().get(0))

    # Reads an unsigned 16-bit little-endian integer from two bytes at `at` as an Int; missing bytes return BinaryError.OutOfRange.
    def uint16_le(at: Int) -> Result[Int, BinaryError]:
        return msrt_bytes_read_word(self, at, 2, True)

    # Reads a signed 16-bit big-endian integer from two bytes at `at`; missing bytes return BinaryError.OutOfRange.
    def int16_be(at: Int) -> Result[Int16, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 2, False)
        return ok(signed(raw, 32768).to_int16().get(0))

    # Reads an unsigned 16-bit big-endian integer from two bytes at `at` as an Int; missing bytes return BinaryError.OutOfRange.
    def uint16_be(at: Int) -> Result[Int, BinaryError]:
        return msrt_bytes_read_word(self, at, 2, False)

    # Reads a signed 32-bit little-endian integer from four bytes at `at`; missing bytes return BinaryError.OutOfRange.
    def int32_le(at: Int) -> Result[Int32, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 4, True)
        return ok(signed(raw, 2147483648).to_int32().get(0))

    # Reads an unsigned 32-bit little-endian integer from four bytes at `at` as an Int; missing bytes return BinaryError.OutOfRange.
    def uint32_le(at: Int) -> Result[Int, BinaryError]:
        return msrt_bytes_read_word(self, at, 4, True)

    # Reads a signed 32-bit big-endian integer from four bytes at `at`; missing bytes return BinaryError.OutOfRange.
    def int32_be(at: Int) -> Result[Int32, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 4, False)
        return ok(signed(raw, 2147483648).to_int32().get(0))

    # Reads an unsigned 32-bit big-endian integer from four bytes at `at` as an Int; missing bytes return BinaryError.OutOfRange.
    def uint32_be(at: Int) -> Result[Int, BinaryError]:
        return msrt_bytes_read_word(self, at, 4, False)

    # Reads a signed 64-bit little-endian integer from eight bytes at `at`; missing bytes return BinaryError.OutOfRange.
    def int64_le(at: Int) -> Result[Int, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 8, True)
        return ok(raw)

    # Reads a signed 64-bit big-endian integer from eight bytes at `at`; missing bytes return BinaryError.OutOfRange.
    def int64_be(at: Int) -> Result[Int, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 8, False)
        return ok(raw)

    # Reads an IEEE 754 binary32 little-endian float from four bytes at `at`; missing bytes return BinaryError.OutOfRange.
    def float32_le(at: Int) -> Result[Float32, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 4, True)
        return ok(msrt_float32_from_bits(raw).to_float32())

    # Reads an IEEE 754 binary32 big-endian float from four bytes at `at`; missing bytes return BinaryError.OutOfRange.
    def float32_be(at: Int) -> Result[Float32, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 4, False)
        return ok(msrt_float32_from_bits(raw).to_float32())

    # Reads an IEEE 754 binary64 little-endian float from eight bytes at `at`; missing bytes return BinaryError.OutOfRange.
    def float64_le(at: Int) -> Result[Float, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 8, True)
        return ok(msrt_float_from_bits(raw))

    # Reads an IEEE 754 binary64 big-endian float from eight bytes at `at`; missing bytes return BinaryError.OutOfRange.
    def float64_be(at: Int) -> Result[Float, BinaryError]:
        let raw = try msrt_bytes_read_word(self, at, 8, False)
        return ok(msrt_float_from_bits(raw))

interface BytesBuilderCodecs:
    var def append_int8(value: Int8) -> Unit
    var def append_int16_le(value: Int16) -> Unit
    var def append_uint16_le(value: Int) -> Unit
    var def append_int16_be(value: Int16) -> Unit
    var def append_uint16_be(value: Int) -> Unit
    var def append_int32_le(value: Int32) -> Unit
    var def append_uint32_le(value: Int) -> Unit
    var def append_int32_be(value: Int32) -> Unit
    var def append_uint32_be(value: Int) -> Unit
    var def append_int64_le(value: Int) -> Unit
    var def append_int64_be(value: Int) -> Unit
    var def append_float32_le(value: Float32) -> Unit
    var def append_float32_be(value: Float32) -> Unit
    var def append_float64_le(value: Float) -> Unit
    var def append_float64_be(value: Float) -> Unit

impl BytesBuilderCodecs for BytesBuilder:
    # Appends one signed byte.
    var def append_int8(value: Int8) -> Unit:
        put_word(var self, value.to_int(), 1, True)

    # Appends a signed 16-bit little-endian integer.
    var def append_int16_le(value: Int16) -> Unit:
        put_word(var self, value.to_int(), 2, True)

    # Appends an unsigned 16-bit little-endian integer; a value outside 0 through 65535 faults.
    var def append_uint16_le(value: Int) -> Unit:
        put_unsigned(var self, value, 65536, 2, True, "append_uint16_le")

    # Appends a signed 16-bit big-endian integer.
    var def append_int16_be(value: Int16) -> Unit:
        put_word(var self, value.to_int(), 2, False)

    # Appends an unsigned 16-bit big-endian integer; a value outside 0 through 65535 faults.
    var def append_uint16_be(value: Int) -> Unit:
        put_unsigned(var self, value, 65536, 2, False, "append_uint16_be")

    # Appends a signed 32-bit little-endian integer.
    var def append_int32_le(value: Int32) -> Unit:
        put_word(var self, value.to_int(), 4, True)

    # Appends an unsigned 32-bit little-endian integer; a value outside 0 through 4294967295 faults.
    var def append_uint32_le(value: Int) -> Unit:
        put_unsigned(var self, value, 4294967296, 4, True, "append_uint32_le")

    # Appends a signed 32-bit big-endian integer.
    var def append_int32_be(value: Int32) -> Unit:
        put_word(var self, value.to_int(), 4, False)

    # Appends an unsigned 32-bit big-endian integer; a value outside 0 through 4294967295 faults.
    var def append_uint32_be(value: Int) -> Unit:
        put_unsigned(var self, value, 4294967296, 4, False, "append_uint32_be")

    # Appends a signed 64-bit little-endian integer.
    var def append_int64_le(value: Int) -> Unit:
        put_word(var self, value, 8, True)

    # Appends a signed 64-bit big-endian integer.
    var def append_int64_be(value: Int) -> Unit:
        put_word(var self, value, 8, False)

    # Appends an IEEE 754 binary32 little-endian float.
    var def append_float32_le(value: Float32) -> Unit:
        put_word(var self, msrt_float32_to_bits(value.to_float()), 4, True)

    # Appends an IEEE 754 binary32 big-endian float.
    var def append_float32_be(value: Float32) -> Unit:
        put_word(var self, msrt_float32_to_bits(value.to_float()), 4, False)

    # Appends an IEEE 754 binary64 little-endian float.
    var def append_float64_le(value: Float) -> Unit:
        put_word(var self, msrt_float_to_bits(value), 8, True)

    # Appends an IEEE 754 binary64 big-endian float.
    var def append_float64_be(value: Float) -> Unit:
        put_word(var self, msrt_float_to_bits(value), 8, False)
