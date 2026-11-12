import (
	Data, Writable from "@std/core.ms",

	msrt_bits_bit_and,
	msrt_bits_shift_right,
	msrt_bytes_join,
	msrt_bytes_read_word,
	msrt_bytes_values,
	msrt_float32_from_bits,
	msrt_float32_to_bits,
	msrt_float_from_bits,
	msrt_float_to_bits from "@std/internal/bytes.ms",
	msrt_bits_bit_or, msrt_bits_shift_left from "@std/internal/math.ms",
)

// An immutable sequence of bytes, such as `"hello".to_bytes()`. Use `decode_utf8()` to
// read text; invalid UTF-8 returns `none`. Indices and slice bounds count bytes from
// zero.
// ms: data
export extern type Bytes

// The bytes themselves, copied.
fn Bytes.as_bytes() Bytes:
	return self.clone()

// Copies byte storage without changing the receiver.
fn Bytes.clone() Bytes: ...

// Tests whether `value` occurs as a byte subsequence.
fn Bytes.contains(value: Bytes) Bool: ...

/*
Splits exact byte separators into a fresh list of immutable byte views.
Nonempty separators retain empty parts; empty data then yields one empty Bytes.
Omitted/none max_parts is unlimited; zero returns no parts, negatives fault.
A cap truncates parts; empty separator yields one Bytes per byte, no parts for empty data.
*/
fn Bytes.split(separator: Bytes, max_parts: Int?) List[Bytes]: ...

/*
Selects [start, end) in bytes; negative bounds are relative to the end.
Bounds outside 0 <= start <= end <= length() return an `Error` of kind `ERANGE`.
The result is a new copy; `view` borrows instead.
*/
fn Bytes.slice(start: Int, end: Int) Bytes!: ...

/*
Borrows [start, end) of the receiver without copying; negative bounds are relative to the end.
Bounds outside 0 <= start <= end <= length() raise a fault. Like `List.get`, the result borrows
the receiver, which cannot change while the view is used; `.clone()` keeps the bytes.
*/
fn Bytes.view(start: Int, end: Int) Bytes: ...

// Returns an unsigned byte; negative indexes are relative to the end. An
// out-of-range index returns `default`, and without one raises a fault.
fn Bytes.get(index: Int, default: UInt8?) UInt8: ...

// Returns the first matching byte offset or `none`; empty `value` matches at zero.
fn Bytes.index_of(value: Bytes) Int?: ...

// Returns the first offset at or after `start` holding the byte `value`, or `none`.
// A `start` past length() gives `none`; a negative `start` counts as zero.
fn Bytes.index_of_byte(value: UInt8, start: Int) Int?: ...

// Returns the last matching byte offset or `none`; empty `value` matches at
// length().
fn Bytes.last_index_of(value: Bytes) Int?: ...

// Tests whether the receiver begins with these bytes.
fn Bytes.starts_with(prefix: Bytes) Bool: ...

// Tests whether the receiver ends with these bytes.
fn Bytes.ends_with(suffix: Bytes) Bool: ...

// Returns a reversed copy without changing the receiver.
fn Bytes.reversed() Bytes: ...

// Returns a copy with one byte replaced; negative indexes are relative to the end.
// An out-of-range index faults.
fn Bytes.with_value(index: Int, value: UInt8) Bytes: ...

// Tests whether the receiver contains no bytes.
fn Bytes.is_empty() Bool: ...

// Returns a fresh mutable list of unsigned byte values; changing it leaves the
// Bytes unchanged.
fn Bytes.values() List[UInt8]: ...

// Returns concatenated bytes without changing either operand.
fn Bytes.concat(other: Bytes) Bytes: ...

// Returns the number of bytes, not the number of Unicode characters.
fn Bytes.length() Int: ...

// Decodes valid UTF-8 as text, or returns `none` when the bytes are invalid.
fn Bytes.decode_utf8() String?: ...

// Decodes [start, end) as `decode_utf8` does, without copying the range into a new
// Bytes first. Bounds outside 0 <= start <= end <= length() raise a fault.
fn Bytes.decode_utf8_range(start: Int, end: Int) String?: ...

// Reads one signed byte at `at`; a missing byte returns an `Error` of kind
// `ERANGE`. Offsets are absolute, so a negative `at` is out of range.
fn Bytes.int8(at: Int) Int8!:
	raw := msrt_bytes_read_word(self, at, 1, true)?
	return ok(signed(raw, 128).to_int8().get(0))

// Reads one unsigned byte at `at`.
fn Bytes.uint8(at: Int) UInt8!:
	raw := msrt_bytes_read_word(self, at, 1, true)?
	return ok(raw.to_uint8().get(0))

// Reads a signed 16-bit little-endian integer from two bytes at `at`; missing bytes
// return an `Error` of kind `ERANGE`.
fn Bytes.int16_le(at: Int) Int16!:
	raw := msrt_bytes_read_word(self, at, 2, true)?
	return ok(signed(raw, 32768).to_int16().get(0))

// Reads an unsigned 16-bit little-endian integer from two bytes at `at`; missing
// bytes return an `Error` of kind `ERANGE`.
fn Bytes.uint16_le(at: Int) UInt16!:
	raw := msrt_bytes_read_word(self, at, 2, true)?
	return ok(raw.to_uint16().get(0))

// Reads a signed 16-bit big-endian integer from two bytes at `at`; missing bytes
// return an `Error` of kind `ERANGE`.
fn Bytes.int16_be(at: Int) Int16!:
	raw := msrt_bytes_read_word(self, at, 2, false)?
	return ok(signed(raw, 32768).to_int16().get(0))

// Reads an unsigned 16-bit big-endian integer from two bytes at `at`; missing bytes
// return an `Error` of kind `ERANGE`.
fn Bytes.uint16_be(at: Int) UInt16!:
	raw := msrt_bytes_read_word(self, at, 2, false)?
	return ok(raw.to_uint16().get(0))

// Reads a signed 32-bit little-endian integer from four bytes at `at`; missing
// bytes return an `Error` of kind `ERANGE`.
fn Bytes.int32_le(at: Int) Int32!:
	raw := msrt_bytes_read_word(self, at, 4, true)?
	return ok(signed(raw, 2147483648).to_int32().get(0))

// Reads an unsigned 32-bit little-endian integer from four bytes at `at`; missing
// bytes return an `Error` of kind `ERANGE`.
fn Bytes.uint32_le(at: Int) UInt32!:
	raw := msrt_bytes_read_word(self, at, 4, true)?
	return ok(raw.to_uint32().get(0))

// Reads a signed 32-bit big-endian integer from four bytes at `at`; missing bytes
// return an `Error` of kind `ERANGE`.
fn Bytes.int32_be(at: Int) Int32!:
	raw := msrt_bytes_read_word(self, at, 4, false)?
	return ok(signed(raw, 2147483648).to_int32().get(0))

// Reads an unsigned 32-bit big-endian integer from four bytes at `at`; missing
// bytes return an `Error` of kind `ERANGE`.
fn Bytes.uint32_be(at: Int) UInt32!:
	raw := msrt_bytes_read_word(self, at, 4, false)?
	return ok(raw.to_uint32().get(0))

// Reads a signed 64-bit little-endian integer from eight bytes at `at`; missing
// bytes return an `Error` of kind `ERANGE`.
fn Bytes.int64_le(at: Int) Int!:
	raw := msrt_bytes_read_word(self, at, 8, true)?
	return ok(raw)

// Reads a signed 64-bit big-endian integer from eight bytes at `at`; missing bytes
// return an `Error` of kind `ERANGE`.
fn Bytes.int64_be(at: Int) Int!:
	raw := msrt_bytes_read_word(self, at, 8, false)?
	return ok(raw)

// Reads an unsigned 64-bit little-endian integer from eight bytes at `at`,
// including the full UInt64 range. Negative offsets or missing bytes return an
// `Error` of kind `ERANGE`.
fn Bytes.uint64_le(at: Int) UInt64!:
	return read_uint64(self, at, true)

// Reads an unsigned 64-bit big-endian integer from eight bytes at `at`, including
// the full UInt64 range. Negative offsets or missing bytes return an `Error` of
// kind `ERANGE`.
fn Bytes.uint64_be(at: Int) UInt64!:
	return read_uint64(self, at, false)

/*
Reads an unsigned base-128 integer, least-significant group first, from absolute byte offset `at`.
Reads at most ten bytes; byte ten must be 0 or 1. Accepts nonminimal encodings and ignores trailing bytes.
Offsets require 0 <= at <= length(), otherwise ERANGE; an unterminated shorter input returns EBADMSG.
*/
fn Bytes.uvarint(at: Int) VarintRead[UInt64]!:
	if at < 0 or at > self.length():
		return error(Error("binary: invalid varint offset", kind: "ERANGE"))

	remaining := self.length() - at
	var word = 0

	for i in 0..10:
		if i >= remaining:
			return error(Error("binary: incomplete varint", kind: "EBADMSG"))

		byte := self.get(at + i).to_int()
		if i == 9 and byte > 1:
			return error(Error("binary: varint overflows 64 bits", kind: "ERANGE"))

		word = msrt_bits_bit_or(
			word,
			msrt_bits_shift_left(msrt_bits_bit_and(byte, 127), i * 7),
		)
		if byte < 128: return ok(VarintRead(unsigned_word(word), at + i + 1))

	return error(Error("binary: varint overflows 64 bits", kind: "ERANGE"))

// Reads a signed 64-bit zigzag integer (0, -1, 1, -2 become 0, 1, 2, 3).
// Shares uvarint's offsets, ten-byte bound, nonminimal acceptance, and error cases.
fn Bytes.varint(at: Int) VarintRead[Int]!:
	raw := self.uvarint(at)?
	half := (raw.value / 2).to_int().get(0)
	if raw.value % 2 == 1: return ok(VarintRead(-half - 1, raw.next_offset))

	return ok(VarintRead(half, raw.next_offset))

// Reads an IEEE 754 binary32 little-endian float from four bytes at `at`; missing
// bytes return an `Error` of kind `ERANGE`.
fn Bytes.float32_le(at: Int) Float32!:
	raw := msrt_bytes_read_word(self, at, 4, true)?
	return ok(msrt_float32_from_bits(raw).to_float32().get(0.0))

// Reads an IEEE 754 binary32 big-endian float from four bytes at `at`; missing
// bytes return an `Error` of kind `ERANGE`.
fn Bytes.float32_be(at: Int) Float32!:
	raw := msrt_bytes_read_word(self, at, 4, false)?
	return ok(msrt_float32_from_bits(raw).to_float32().get(0.0))

// Reads an IEEE 754 binary64 little-endian float from eight bytes at `at`; missing
// bytes return an `Error` of kind `ERANGE`.
fn Bytes.float64_le(at: Int) Float!:
	raw := msrt_bytes_read_word(self, at, 8, true)?
	return ok(msrt_float_from_bits(raw))

// Reads an IEEE 754 binary64 big-endian float from eight bytes at `at`; missing
// bytes return an `Error` of kind `ERANGE`.
fn Bytes.float64_be(at: Int) Float!:
	raw := msrt_bytes_read_word(self, at, 8, false)?
	return ok(msrt_float_from_bits(raw))

// Returns the parts end to end as one new Bytes; an empty list gives empty bytes. One
// allocation and one copy of each part, unlike repeated concat.
export fn join(parts: List[Bytes]) Bytes:
	return msrt_bytes_join(parts)

// Returns a fresh mutable list of bytes, like data.values().
export fn values(data: Bytes) List[UInt8]:
	return msrt_bytes_values(data)

// Builds a byte sequence efficiently before freezing it into an immutable value.
export extern type BytesBuilder

// Appends one byte to the end of the builder.
fn var BytesBuilder.append(value: UInt8) Unit: ...

// Appends all supplied bytes in order; the input is unchanged.
fn var BytesBuilder.append_bytes(values: Bytes) Unit: ...

// Consumes the builder and returns its bytes; the builder cannot be used
// afterwards.
fn BytesBuilder.build() Bytes: ...

// Returns the bytes appended so far and leaves the builder empty, for a builder
// held in a field.
fn var BytesBuilder.drain() Bytes: ...

// Appends one signed byte.
fn var BytesBuilder.append_int8(value: Int8) Unit:
	put_word(var self, value.to_int(), 1, true)

// Appends a signed 16-bit little-endian integer.
fn var BytesBuilder.append_int16_le(value: Int16) Unit:
	put_word(var self, value.to_int(), 2, true)

// Appends an unsigned 16-bit little-endian integer.
fn var BytesBuilder.append_uint16_le(value: UInt16) Unit:
	put_word(var self, value.to_int(), 2, true)

// Appends a signed 16-bit big-endian integer.
fn var BytesBuilder.append_int16_be(value: Int16) Unit:
	put_word(var self, value.to_int(), 2, false)

// Appends an unsigned 16-bit big-endian integer.
fn var BytesBuilder.append_uint16_be(value: UInt16) Unit:
	put_word(var self, value.to_int(), 2, false)

// Appends a signed 32-bit little-endian integer.
fn var BytesBuilder.append_int32_le(value: Int32) Unit:
	put_word(var self, value.to_int(), 4, true)

// Appends an unsigned 32-bit little-endian integer.
fn var BytesBuilder.append_uint32_le(value: UInt32) Unit:
	put_word(var self, value.to_int(), 4, true)

// Appends a signed 32-bit big-endian integer.
fn var BytesBuilder.append_int32_be(value: Int32) Unit:
	put_word(var self, value.to_int(), 4, false)

// Appends an unsigned 32-bit big-endian integer.
fn var BytesBuilder.append_uint32_be(value: UInt32) Unit:
	put_word(var self, value.to_int(), 4, false)

// Appends a signed 64-bit little-endian integer.
fn var BytesBuilder.append_int64_le(value: Int) Unit:
	put_word(var self, value, 8, true)

// Appends a signed 64-bit big-endian integer.
fn var BytesBuilder.append_int64_be(value: Int) Unit:
	put_word(var self, value, 8, false)

// Appends an unsigned 64-bit little-endian integer, including the full UInt64
// range.
fn var BytesBuilder.append_uint64_le(value: UInt64) Unit:
	put_uint64(var self, value, true)

// Appends an unsigned 64-bit big-endian integer, including the full UInt64 range.
fn var BytesBuilder.append_uint64_be(value: UInt64) Unit:
	put_uint64(var self, value, false)

// Appends the shortest unsigned base-128 encoding, from one through ten bytes.
fn var BytesBuilder.append_uvarint(value: UInt64) Unit:
	var remaining = value

	while remaining >= 128:
		self.append((remaining % 128).to_uint8().get(0) + 128)
		remaining /= 128

	self.append(remaining.to_uint8().get(0))

// Appends the shortest signed 64-bit zigzag encoding; even the most negative Int
// fits in ten bytes.
fn var BytesBuilder.append_varint(value: Int) Unit:
	if value < 0:
		self.append_uvarint((-(value + 1)).to_uint64().get(0) * 2 + 1)
		return unit

	self.append_uvarint(value.to_uint64().get(0) * 2)

// Appends an IEEE 754 binary32 little-endian float.
fn var BytesBuilder.append_float32_le(value: Float32) Unit:
	put_word(var self, msrt_float32_to_bits(value.to_float()), 4, true)

// Appends an IEEE 754 binary32 big-endian float.
fn var BytesBuilder.append_float32_be(value: Float32) Unit:
	put_word(var self, msrt_float32_to_bits(value.to_float()), 4, false)

// Appends an IEEE 754 binary64 little-endian float.
fn var BytesBuilder.append_float64_le(value: Float) Unit:
	put_word(var self, msrt_float_to_bits(value), 8, true)

// Appends an IEEE 754 binary64 big-endian float.
fn var BytesBuilder.append_float64_be(value: Float) Unit:
	put_word(var self, msrt_float_to_bits(value), 8, false)

// A decoded variable-length integer and the absolute offset of the next byte.
// Example: `first := data.uvarint(0)?; second := data.varint(first.next_offset)?`.
export type VarintRead[T]:
	// The integer decoded as unsigned base-128 or signed zigzag by the read method.
	value: T
	// The first byte after the encoding, relative to the receiver, including for a
	// slice.
	next_offset: Int

// Appends the low `width` bytes of `value` in the requested byte order.
fn put_word(var out: BytesBuilder, value: Int, width: Int, little: Bool) Unit:
	for i in 0..width:
		place := if little: i else: width - 1 - i
		out.append(
			msrt_bits_bit_and(
				msrt_bits_shift_right(value, 8 * place),
				255,
			).to_uint8().get(0)
		)

// Reads a signed value from its unsigned bit pattern: `half` is 2 to the power
// `bits - 1`.
fn signed(raw: Int, half: Int) Int:
	if raw >= half: return raw - half * 2
	return raw

// Converts a 64-bit word without narrowing its unsigned upper half.
fn unsigned_word(raw: Int) UInt64:
	if raw >= 0: return raw.to_uint64().get(0)
	return (raw + 9223372036854775807 + 1).to_uint64().get(0) + 9223372036854775808

// Reads the full word and preserves its unsigned upper half.
fn read_uint64(data: Bytes, at: Int, little: Bool) UInt64!:
	if at < 0 or at > data.length() - 8:
		return error(Error("binary: out of range", kind: "ERANGE"))
	return ok(unsigned_word(msrt_bytes_read_word(data, at, 8, little)?))

fn put_uint64(var out: BytesBuilder, value: UInt64, little: Bool) Unit:
	high := (value / 4294967296).to_int().get(0)
	low := (value % 4294967296).to_int().get(0)

	if little:
		put_word(var out, low, 4, true)
		put_word(var out, high, 4, true)
		return unit

	put_word(var out, high, 4, false)
	put_word(var out, low, 4, false)
