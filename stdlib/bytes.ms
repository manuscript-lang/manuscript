import Data from "@std/core.ms"
import (
    msrt_bytes_join,
    msrt_bytes_values,
    msrt_bytes_read_word,
    msrt_float_from_bits,
    msrt_float_to_bits,
    msrt_float32_from_bits,
    msrt_float32_to_bits,
    msrt_bits_bit_and,
    msrt_bits_shift_right
) from "@std/internal/bytes.ms"
import msrt_bits_bit_or, msrt_bits_shift_left from "@std/internal/math.ms"

# An immutable sequence of bytes. Indices and slice bounds are zero-based.
export extern type Bytes

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
    fn split(separator: Bytes, max_parts: Int?) List[Bytes]: ...

    # Selects [start, end) in bytes; negative bounds are relative to the end.
    # Bounds outside 0 <= start <= end <= length() return an `Error` of kind `OutOfRange`.
    # The immutable result may share storage with the receiver.
    fn slice(start: Int, end: Int) Bytes!: ...

    # Returns an unsigned byte; negative indexes are relative to the end. An out-of-range index returns `default`, and without one raises a fault.
    fn get(index: Int, default: UInt8?) UInt8: ...

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
export fn join(parts: List[Bytes]) Bytes:
    return msrt_bytes_join(parts)

# Returns a fresh mutable list of bytes, like data.values().
export fn values(data: Bytes) List[UInt8]:
    return msrt_bytes_values(data)

# Builds a byte sequence efficiently before freezing it into an immutable value.
export extern type BytesBuilder

impl BytesBuilder:
    # Appends one byte to the end of the builder.
    var fn append(value: UInt8) Unit: ...

    # Appends all supplied bytes in order; the input is unchanged.
    var fn append_bytes(values: Bytes) Unit: ...

    # Consumes the builder and returns its bytes; the builder cannot be used afterwards.
    fn build() Bytes: ...

    # Returns the bytes appended so far and leaves the builder empty, for a builder held in a field.
    var fn drain() Bytes: ...

# A decoded variable-length integer and the absolute offset of the next byte.
# Example: `let first = try data.uvarint(0); let second = try data.varint(first.next_offset)`.
export type VarintRead[T]:
    # The integer decoded as unsigned base-128 or signed zigzag by the read method.
    value: T
    # The first byte after the encoding, relative to the receiver, including for a slice.
    next_offset: Int

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

# Converts a 64-bit word without narrowing its unsigned upper half.
fn unsigned_word(raw: Int) UInt64:
    if raw >= 0:
        return raw.to_uint64().get(0)

    return (raw + 9223372036854775807 + 1).to_uint64().get(0) + 9223372036854775808

# Reads two unsigned halves so the top bit never passes through a signed conversion.
fn read_uint64(data: Bytes, at: Int, little: Bool) UInt64!:
    if at < 0 or at > data.length() - 8:
        return error(Error("binary: out of range", kind: OutOfRange))

    let first = try msrt_bytes_read_word(data, at, 4, little)
    let second = try msrt_bytes_read_word(data, at + 4, 4, little)
    if little:
        return ok(second.to_uint64().get(0) * 4294967296 + first.to_uint64().get(0))

    return ok(first.to_uint64().get(0) * 4294967296 + second.to_uint64().get(0))

fn put_uint64(var out: BytesBuilder, value: UInt64, little: Bool) Unit:
    let high = (value / 4294967296).to_int().get(0)
    let low = (value % 4294967296).to_int().get(0)

    if little:
        put_word(var out, low, 4, true)
        put_word(var out, high, 4, true)
        return unit

    put_word(var out, high, 4, false)
    put_word(var out, low, 4, false)

interface BytesCodecs:
    fn int8(at: Int) Int8!
    fn uint8(at: Int) UInt8!
    fn int16_le(at: Int) Int16!
    fn uint16_le(at: Int) UInt16!
    fn int16_be(at: Int) Int16!
    fn uint16_be(at: Int) UInt16!
    fn int32_le(at: Int) Int32!
    fn uint32_le(at: Int) UInt32!
    fn int32_be(at: Int) Int32!
    fn uint32_be(at: Int) UInt32!
    fn int64_le(at: Int) Int!
    fn int64_be(at: Int) Int!
    fn uint64_le(at: Int) UInt64!
    fn uint64_be(at: Int) UInt64!
    fn uvarint(at: Int) VarintRead[UInt64]!
    fn varint(at: Int) VarintRead[Int]!
    fn float32_le(at: Int) Float32!
    fn float32_be(at: Int) Float32!
    fn float64_le(at: Int) Float!
    fn float64_be(at: Int) Float!

impl BytesCodecs for Bytes:
    # Reads one signed byte at `at`; a missing byte returns an `Error` of kind `OutOfRange`. Offsets are absolute, so a negative `at` is out of range.
    fn int8(at: Int) Int8!:
        let raw = try msrt_bytes_read_word(self, at, 1, true)
        return ok(signed(raw, 128).to_int8().get(0))

    # Reads one unsigned byte at `at`.
    fn uint8(at: Int) UInt8!:
        let raw = try msrt_bytes_read_word(self, at, 1, true)
        return ok(raw.to_uint8().get(0))

    # Reads a signed 16-bit little-endian integer from two bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn int16_le(at: Int) Int16!:
        let raw = try msrt_bytes_read_word(self, at, 2, true)
        return ok(signed(raw, 32768).to_int16().get(0))

    # Reads an unsigned 16-bit little-endian integer from two bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn uint16_le(at: Int) UInt16!:
        let raw = try msrt_bytes_read_word(self, at, 2, true)
        return ok(raw.to_uint16().get(0))

    # Reads a signed 16-bit big-endian integer from two bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn int16_be(at: Int) Int16!:
        let raw = try msrt_bytes_read_word(self, at, 2, false)
        return ok(signed(raw, 32768).to_int16().get(0))

    # Reads an unsigned 16-bit big-endian integer from two bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn uint16_be(at: Int) UInt16!:
        let raw = try msrt_bytes_read_word(self, at, 2, false)
        return ok(raw.to_uint16().get(0))

    # Reads a signed 32-bit little-endian integer from four bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn int32_le(at: Int) Int32!:
        let raw = try msrt_bytes_read_word(self, at, 4, true)
        return ok(signed(raw, 2147483648).to_int32().get(0))

    # Reads an unsigned 32-bit little-endian integer from four bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn uint32_le(at: Int) UInt32!:
        let raw = try msrt_bytes_read_word(self, at, 4, true)
        return ok(raw.to_uint32().get(0))

    # Reads a signed 32-bit big-endian integer from four bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn int32_be(at: Int) Int32!:
        let raw = try msrt_bytes_read_word(self, at, 4, false)
        return ok(signed(raw, 2147483648).to_int32().get(0))

    # Reads an unsigned 32-bit big-endian integer from four bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn uint32_be(at: Int) UInt32!:
        let raw = try msrt_bytes_read_word(self, at, 4, false)
        return ok(raw.to_uint32().get(0))

    # Reads a signed 64-bit little-endian integer from eight bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn int64_le(at: Int) Int!:
        let raw = try msrt_bytes_read_word(self, at, 8, true)
        return ok(raw)

    # Reads a signed 64-bit big-endian integer from eight bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn int64_be(at: Int) Int!:
        let raw = try msrt_bytes_read_word(self, at, 8, false)
        return ok(raw)

    # Reads an unsigned 64-bit little-endian integer from eight bytes at `at`, including the full UInt64 range.
    # Negative offsets or missing bytes return an `Error` of kind `OutOfRange`.
    fn uint64_le(at: Int) UInt64!:
        return read_uint64(self, at, true)

    # Reads an unsigned 64-bit big-endian integer from eight bytes at `at`, including the full UInt64 range.
    # Negative offsets or missing bytes return an `Error` of kind `OutOfRange`.
    fn uint64_be(at: Int) UInt64!:
        return read_uint64(self, at, false)

    # Reads an unsigned base-128 integer, least-significant group first, from absolute byte offset `at`.
    # Reads at most ten bytes; byte ten must be 0 or 1. Accepts nonminimal encodings and ignores trailing bytes.
    # Offsets require 0 <= at <= length(); an unterminated shorter input is Incomplete.
    fn uvarint(at: Int) VarintRead[UInt64]!:
        if at < 0 or at > self.length():
            return error(Error("binary: invalid varint offset", kind: OutOfRange))

        let remaining = self.length() - at
        var word = 0

        for i in 0..10:
            if i >= remaining:
                return error(Error("binary: incomplete varint", kind: InvalidData))

            let byte = self.get(at + i).to_int()
            if i == 9 and byte > 1:
                return error(
                    Error(
                        "binary: varint overflows 64 bits", kind: OutOfRange
                    )
                )

            word = msrt_bits_bit_or(
                word,
                msrt_bits_shift_left(
                    msrt_bits_bit_and(byte, 127), i * 7
                )
            )
            if byte < 128:
                return ok(VarintRead(unsigned_word(word), at + i + 1))

        return error(Error("binary: varint overflows 64 bits", kind: OutOfRange))

    # Reads a signed 64-bit zigzag integer (0, -1, 1, -2 become 0, 1, 2, 3).
    # Shares uvarint's offsets, ten-byte bound, nonminimal acceptance, and error cases.
    fn varint(at: Int) VarintRead[Int]!:
        let raw = try self.uvarint(at)
        let half = (raw.value / 2).to_int().get(0)
        if raw.value % 2 == 1:
            return ok(VarintRead(-half - 1, raw.next_offset))

        return ok(VarintRead(half, raw.next_offset))

    # Reads an IEEE 754 binary32 little-endian float from four bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn float32_le(at: Int) Float32!:
        let raw = try msrt_bytes_read_word(self, at, 4, true)
        return ok(msrt_float32_from_bits(raw).to_float32().get(0.0))

    # Reads an IEEE 754 binary32 big-endian float from four bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn float32_be(at: Int) Float32!:
        let raw = try msrt_bytes_read_word(self, at, 4, false)
        return ok(msrt_float32_from_bits(raw).to_float32().get(0.0))

    # Reads an IEEE 754 binary64 little-endian float from eight bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn float64_le(at: Int) Float!:
        let raw = try msrt_bytes_read_word(self, at, 8, true)
        return ok(msrt_float_from_bits(raw))

    # Reads an IEEE 754 binary64 big-endian float from eight bytes at `at`; missing bytes return an `Error` of kind `OutOfRange`.
    fn float64_be(at: Int) Float!:
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
    var fn append_uint64_le(value: UInt64) Unit
    var fn append_uint64_be(value: UInt64) Unit
    var fn append_uvarint(value: UInt64) Unit
    var fn append_varint(value: Int) Unit
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

    # Appends an unsigned 64-bit little-endian integer, including the full UInt64 range.
    var fn append_uint64_le(value: UInt64) Unit:
        put_uint64(var self, value, true)

    # Appends an unsigned 64-bit big-endian integer, including the full UInt64 range.
    var fn append_uint64_be(value: UInt64) Unit:
        put_uint64(var self, value, false)

    # Appends the shortest unsigned base-128 encoding, from one through ten bytes.
    var fn append_uvarint(value: UInt64) Unit:
        var remaining = value

        while remaining >= 128:
            self.append((remaining % 128).to_uint8().get(0) + 128)
            remaining /= 128

        self.append(remaining.to_uint8().get(0))

    # Appends the shortest signed 64-bit zigzag encoding; even the most negative Int fits in ten bytes.
    var fn append_varint(value: Int) Unit:
        if value < 0:
            self.append_uvarint((-(value + 1)).to_uint64().get(0) * 2 + 1)
            return unit

        self.append_uvarint(value.to_uint64().get(0) * 2)

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
