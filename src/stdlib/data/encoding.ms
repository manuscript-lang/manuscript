import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	from_scalars from "@std/string.ms",

	msstd_encoding_base64_decode,
	msstd_encoding_base64_decode_unpadded,
	msstd_encoding_base64_encode_unpadded from "@std/internal/encoding.ms",
	msrt_bits_bit_and,
	msrt_bits_bit_or,
	msrt_bits_shift_left,
	msrt_bits_shift_right_unsigned from "@std/internal/math.ms",
)

/*
Binary-to-text encodings (ASCII85, Base32, Base64, hexadecimal) and text encodings
(UTF-16, ISO-8859-1, ASCII) over `Bytes`. Decoders return an `Error` with kind `EBADMSG`
for malformed input. Where a decoder takes `max_bytes`, a negative value returns
`EINVAL` and output above the limit returns `EOVERFLOW`; pass it when the input is
untrusted. `@std/data/encoding_stream.ms` has the streaming forms.
*/

// Encodes unframed ASCII85; complete groups of four zero bytes become `z`. No Adobe
// `<~`/`~>` delimiters are added. Example: `ascii85_encode("hello".to_bytes())` is
// `"BOu!rDZ"`.
export fn ascii85_encode(data Bytes) String {
	size := data.length()
	var out = BytesBuilder()
	var at = 0

	while at + 4 <= size {
		word := (
			data.get(at).to_int() * 16777216
			+ data.get(at + 1).to_int() * 65536
			+ data.get(at + 2).to_int() * 256
			+ data.get(at + 3).to_int()
		)
		at += 4

		if word == 0 {
			out.append(122)
			continue
		}

		r0 := word % 52200625
		r1 := r0 % 614125
		r2 := r1 % 7225
		out.append((33 + word / 52200625).to_uint8() or 0)
		out.append((33 + r0 / 614125).to_uint8() or 0)
		out.append((33 + r1 / 7225).to_uint8() or 0)
		out.append((33 + r2 / 85).to_uint8() or 0)
		out.append((33 + r2 % 85).to_uint8() or 0)
	}

	if at < size {
		var word = 0

		for k in 0..4 {
			byte := if at + k < size {
				data.get(at + k).to_int()
			} else {
				0
			}
			word = word * 256 + byte
		}

		put_digits(out, word, size - at + 1)
	}

	return out.build().decode_utf8() or ""
}

// Appends the first `count` of the five base-85 digits of the 32-bit `word`.
fn put_digits(var out BytesBuilder, word, count Int) Void {
	d0 := word / 52200625
	r0 := word % 52200625
	d1 := r0 / 614125
	r1 := r0 % 614125
	d2 := r1 / 7225
	r2 := r1 % 7225
	d3 := r2 / 85
	d4 := r2 % 85
	out.append((33 + d0).to_uint8() or 0)
	out.append((33 + d1).to_uint8() or 0)
	if count > 2 { out.append((33 + d2).to_uint8() or 0) }
	if count > 3 { out.append((33 + d3).to_uint8() or 0) }
	if count > 4 { out.append((33 + d4).to_uint8() or 0) }
}

/*
Decodes unframed ASCII85. ASCII bytes 0 through 32 are ignored, and `z` is valid only between groups.
Rejects Adobe delimiters, one-digit tails, invalid characters and groups that overflow 32 bits.
A negative `max_bytes` returns `EINVAL`; decoded output above it returns `EOVERFLOW` before the output is allocated.
*/
export fn ascii85_decode(text String, max_bytes Int?) Bytes! {
	if is_negative(max_bytes) { return invalid_input() }

	room := budget(max_bytes)
	data := text.view_bytes()
	size := data.length()
	var out = BytesBuilder()
	var made = 0
	var word = 0
	var digits = 0
	var i = 0

	while i < size {
		if digits == 0 and i + 5 <= size {
			// Five digits in a row: a whole group without the per-byte state. A digit
			// is under 85 and any other byte is 255, so no byte is a digit exactly when
			// the or of the five has bit 7 set.
			d0 := ASCII85_VALUES[data.get(i).to_int()]
			d1 := ASCII85_VALUES[data.get(i + 1).to_int()]
			d2 := ASCII85_VALUES[data.get(i + 2).to_int()]
			d3 := ASCII85_VALUES[data.get(i + 3).to_int()]
			d4 := ASCII85_VALUES[data.get(i + 4).to_int()]

			if (
				msrt_bits_bit_or(
					msrt_bits_bit_or(d0, d1),
					msrt_bits_bit_or(msrt_bits_bit_or(d2, d3), d4),
				) < 128
			) {
				group := (
					(
						(
							(
								masked(d0) * 85
								+ masked(d1)
							) * 85
							+ masked(d2)
						) * 85
						+ masked(d3)
					) * 85
					+ masked(d4)
				)
				if group > 4294967295 { return invalid_data() }
				if 4 > room - made { return limit_exceeded() }

				out.append(msrt_bits_shift_right_unsigned(group, 24).to_uint8() or 0)
				out.append(
					msrt_bits_bit_and(
						msrt_bits_shift_right_unsigned(
							group,
							16,
						),
						255,
					).to_uint8() or 0
				)
				out.append(
					msrt_bits_bit_and(
						msrt_bits_shift_right_unsigned(
							group,
							8,
						),
						255,
					).to_uint8() or 0
				)
				out.append(msrt_bits_bit_and(group, 255).to_uint8() or 0)
				made += 4
				i += 5
				continue
			}
		}

		c := data.get(i).to_int()
		i += 1
		if c <= 32 { continue }

		if c == 122 {
			if digits != 0 { return invalid_data() }
			if 4 > room - made { return limit_exceeded() }

			for zero in 0..4 { out.append(0) }
			made += 4
			continue
		}

		if c < 33 or c > 117 { return invalid_data() }

		word = word * 85 + (c - 33)
		digits += 1

		if digits == 5 {
			if word > 4294967295 { return invalid_data() }
			if 4 > room - made { return limit_exceeded() }

			put_group(out, word, 4)
			made += 4
			word = 0
			digits = 0
		}
	}

	if digits == 1 { return invalid_data() }

	if digits > 1 {
		for pad in digits..5 { word = word * 85 + 84 }
		if word > 4294967295 { return invalid_data() }
		if digits - 1 > room - made { return limit_exceeded() }

		put_group(out, word, digits - 1)
	}

	return ok(out.build())
}

// Appends the first `count` bytes of the 32-bit `word`, most significant first.
fn put_group(var out BytesBuilder, word, count Int) Void {
	out.append(
		msrt_bits_bit_and(
			msrt_bits_shift_right_unsigned(word, 24),
			255,
		).to_uint8() or 0
	)
	if count > 1 {
		out.append(
			msrt_bits_bit_and(
				msrt_bits_shift_right_unsigned(word, 16),
				255,
			).to_uint8() or 0
		)
	}
	if count > 2 {
		out.append(
			msrt_bits_bit_and(
				msrt_bits_shift_right_unsigned(word, 8),
				255,
			).to_uint8() or 0
		)
	}
	if count > 3 { out.append(msrt_bits_bit_and(word, 255).to_uint8() or 0) }
}

// Alphabet and padding for `base32_encode` and `base32_decode`.
export type Base32Options {
	// True selects the extended hex alphabet 0-9/A-V.
	hex_alphabet Bool = false
	// False omits (or forbids) the `=` padding.
	padded Bool = true
}

// Encodes uppercase RFC 4648 Base32, using the alphabet and padding in `options`.
// Example: `base32_encode("f".to_bytes())` returns `"MY======"`.
export fn base32_encode(data Bytes, options Base32Options = Base32Options()) String {
	symbols := if options.hex_alphabet { BASE32_HEX_SYMBOLS } else { BASE32_SYMBOLS }
	size := data.length()
	var out = BytesBuilder()
	var at = 0

	while at + 5 <= size {
		word := (
			data.get(at).to_int() * 4294967296
			+ data.get(at + 1).to_int() * 16777216
			+ data.get(at + 2).to_int() * 65536
			+ data.get(at + 3).to_int() * 256
			+ data.get(at + 4).to_int()
		)
		at += 5
		for k in 0..8 {
			out.append(
				symbols[
					msrt_bits_bit_and(
						msrt_bits_shift_right_unsigned(
							word,
							35 - 5 * k,
						),
						31,
					)
				]
			)
		}
	}

	var written = at / 5 * 8
	var accumulator = 0
	var held = 0

	for i in at..size {
		accumulator = msrt_bits_bit_or(
			msrt_bits_shift_left(accumulator, 8),
			data.get(i).to_int(),
		)
		held += 8

		while held >= 5 {
			held -= 5
			out.append(
				symbols[
					msrt_bits_bit_and(
						msrt_bits_shift_right_unsigned(
							accumulator,
							held,
						),
						31,
					)
				]
			)
			written += 1
		}

		accumulator = msrt_bits_bit_and(accumulator, msrt_bits_shift_left(1, held) - 1)
	}

	if held > 0 {
		out.append(
			symbols[
				msrt_bits_bit_and(
					msrt_bits_shift_left(accumulator, 5 - held),
					31,
				)
			]
		)
		written += 1
	}

	if options.padded {
		while written % 8 != 0 {
			out.append(61)
			written += 1
		}
	}

	return out.build().decode_utf8() or ""
}

/*
Decodes uppercase RFC 4648 Base32, or 0-9/A-V when `options.hex_alphabet` is true.
Padding must be exact and only at the end; `padded: false` forbids `=`. Whitespace and nonzero unused bits return `EBADMSG`.
A negative `max_bytes` returns `EINVAL`; output exceeding it returns `EOVERFLOW`.
*/
export fn base32_decode(
	text String,
	options Base32Options = Base32Options(),
	max_bytes Int? = null,
) Bytes! {
	if is_negative(max_bytes) { return invalid_input() }

	data := text.view_bytes()
	size := data.length()
	var padding = 0
	while padding < size and data.get(
		size - 1 - padding
	) == 61 { padding += 1 }

	count := size - padding

	// Padding belongs only to padded text and completes its last block; a last block of
	// 1, 3 or 6 symbols holds no bytes.
	tail := count % 8
	tail_ok := tail == 0 or tail == 2 or tail == 4 or tail == 5 or tail == 7
	if (
		(padding > 0 and not options.padded)
		or (options.padded and size % 8 != 0)
		or not tail_ok
		or (options.padded and padding != (8 - tail) % 8)
	) { return invalid_data() }

	if count / 8 * 5 + count % 8 * 5 / 8 > budget(max_bytes) {
		// An `=` before the padding is bad data whatever the budget.
		for i in 0..count {
			if data.get(i) == 61 { return invalid_data() }
		}
		return limit_exceeded()
	}

	values := if options.hex_alphabet { BASE32_HEX_VALUES } else { BASE32_VALUES }
	var out = BytesBuilder()
	var at = 0

	while at + 8 <= count {
		d0 := values[data.get(at).to_int()]
		d1 := values[data.get(at + 1).to_int()]
		d2 := values[data.get(at + 2).to_int()]
		d3 := values[data.get(at + 3).to_int()]
		d4 := values[data.get(at + 4).to_int()]
		d5 := values[data.get(at + 5).to_int()]
		d6 := values[data.get(at + 6).to_int()]
		d7 := values[data.get(at + 7).to_int()]
		if (
			msrt_bits_bit_or(
				msrt_bits_bit_or(
					msrt_bits_bit_or(d0, d1),
					msrt_bits_bit_or(d2, d3),
				),
				msrt_bits_bit_or(
					msrt_bits_bit_or(d4, d5),
					msrt_bits_bit_or(d6, d7),
				),
			) > 31
		) {
			return invalid_data()
		}

		word := (
			masked(d0) * 34359738368
			+ masked(d1) * 1073741824
			+ masked(d2) * 33554432
			+ masked(d3) * 1048576
			+ masked(d4) * 32768
			+ masked(d5) * 1024
			+ masked(d6) * 32
			+ masked(d7)
		)
		at += 8
		for k in 0..5 {
			out.append(
				msrt_bits_bit_and(
					msrt_bits_shift_right_unsigned(
						word,
						32 - 8 * k,
					),
					255,
				).to_uint8() or 0
			)
		}
	}

	var accumulator = 0
	var held = 0

	for i in at..count {
		digit := values[data.get(i).to_int()]
		if digit == 255 { return invalid_data() }

		accumulator = msrt_bits_bit_or(msrt_bits_shift_left(accumulator, 5), digit)
		held += 5

		if held >= 8 {
			held -= 8
			out.append(
				msrt_bits_bit_and(
					msrt_bits_shift_right_unsigned(
						accumulator,
						held,
					),
					255,
				).to_uint8() or 0
			)
			accumulator = msrt_bits_bit_and(
				accumulator,
				msrt_bits_shift_left(1, held) - 1,
			)
		}
	}

	if accumulator != 0 { return invalid_data() }

	return ok(out.build())
}

/*
Decodes standard Base64 by default; set `url_safe: true` for the URL-safe alphabet.
`padded: false` expects text without `=` and rejects `=`. Whitespace and nonzero unused bits are always rejected.
Malformed text returns `EBADMSG`; `max_bytes` behaves as in `base32_decode`.
*/
export fn base64_decode(
	text String,
	url_safe Bool = false,
	padded Bool = true,
	max_bytes Int? = null,
) Bytes! {
	if not padded {
		return msstd_encoding_base64_decode_unpadded(text, url_safe, max_bytes)
	}
	return msstd_encoding_base64_decode(text, url_safe, max_bytes)
}

// The budget as a count: no budget is the largest `Int`, and a negative budget stays
// negative.
fn budget(max_bytes Int?) Int {
	limit := max_bytes
	if limit != null { return limit }

	return 9223372036854775807
}

// Encodes bytes as standard Base64 by default; set `url_safe: true` for URL-safe text
// and `padded: false` to omit `=`. Example:
// `base64_encode("f".to_bytes(), padded: false)` returns `"Zg"`.
export fn base64_encode(data Bytes, url_safe Bool = false, padded Bool = true) String {
	if not padded { return msstd_encoding_base64_encode_unpadded(data, url_safe) }
	if data.is_empty() { return "" }

	text := msstd_encoding_base64_encode_unpadded(data, url_safe)
	tail := data.length() % 3
	if tail == 1 { return text + "==" }
	if tail == 2 { return text + "=" }

	return text
}

// Decodes hexadecimal text, upper or lower case. Odd length or a non-hex character
// returns
// `EBADMSG`. `max_bytes` bounds decoded output as in `base32_decode`.
export fn hex_decode(text String, max_bytes Int?) Bytes! {
	if is_negative(max_bytes) { return invalid_input() }

	data := text.view_bytes()
	half := data.length() / 2
	if half > budget(max_bytes) { return limit_exceeded() }
	if data.length() % 2 != 0 { return invalid_data() }

	var out = BytesBuilder()

	for i in 0..half {
		high := HEX_VALUES[data.get(2 * i).to_int()]
		low := HEX_VALUES[data.get(2 * i + 1).to_int()]
		if msrt_bits_bit_or(high, low) > 15 { return invalid_data() }

		out.append((masked(high) * 16 + masked(low)).to_uint8() or 0)
	}

	return ok(out.build())
}

// Encodes each byte as two lowercase hexadecimal digits.
export fn hex_encode(data Bytes) String {
	var out = BytesBuilder()

	for i in 0..data.length() {
		byte := data.get(i).to_int()
		out.append(HEX_SYMBOLS[byte / 16])
		out.append(HEX_SYMBOLS[byte % 16])
	}

	return out.build().decode_utf8() or ""
}

// Encodes text as UTF-16 code units, little-endian unless `little_endian` is false.
// No byte order mark is written.
export fn utf16_encode(text String, little_endian Bool = true) Bytes {
	var out = BytesBuilder()

	for scalar in text.scalar_values() {
		if scalar < 65536 {
			append_unit(out, scalar, little_endian)
		} else {
			offset := scalar - 65536
			append_unit(out, 55296 + offset / 1024, little_endian)
			append_unit(out, 56320 + offset % 1024, little_endian)
		}
	}

	return out.build()
}

fn append_unit(var out BytesBuilder, code Int, little_endian Bool) Void {
	if little_endian {
		out.append(byte_of(code % 256))
		out.append(byte_of(code / 256))
	} else {
		out.append(byte_of(code / 256))
		out.append(byte_of(code % 256))
	}
}

// UTF-8 byte length of one scalar.
fn utf8_length(scalar Int) Int {
	if scalar < 128 { return 1 }
	if scalar < 2048 { return 2 }
	if scalar < 65536 { return 3 }

	return 4
}

// A byte from a count already known to be 0 through 255.
fn byte_of(n Int) UInt8 {
	return n.to_uint8() or 0
}

fn text_of(scalars List[Int]) String {
	if text := from_scalars(scalars) { return text }
	return ""
}

// Decodes UTF-16 bytes, little-endian unless `little_endian` is false. An odd length or
// an unpaired surrogate returns `EBADMSG`; a negative `max_bytes` returns `EINVAL`, and
// decoded text longer than `max_bytes` UTF-8 bytes returns `EOVERFLOW`.
export fn utf16_decode(data Bytes, little_endian Bool = true, max_bytes Int?) String! {
	limit := budget(max_bytes)
	if limit < 0 { return error(Error("encoding: invalid input", kind: "EINVAL")) }

	bytes := data.values()
	if bytes.length() % 2 != 0 { return error(encoding_invalid_data()) }

	var units = List[Int]()

	for pair in 0..(bytes.length() / 2) {
		low := bytes[pair * 2].to_int()
		high := bytes[pair * 2 + 1].to_int()

		if little_endian {
			units.append(low + high * 256)
		} else {
			units.append(low * 256 + high)
		}
	}

	var scalars = List[Int]()
	var size = 0
	var index = 0

	while index < units.length() {
		code := units[index]
		var scalar = code
		index += 1
		if code >= 56320 and code < 57344 { return error(encoding_invalid_data()) }

		if code >= 55296 and code < 56320 {
			if index >= units.length() { return error(encoding_invalid_data()) }

			next := units[index]
			if next < 56320 or next >= 57344 { return error(encoding_invalid_data()) }

			scalar = 65536 + (code - 55296) * 1024 + (next - 56320)
			index += 1
		}

		size += utf8_length(scalar)
		if size > limit {
			return error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
		}

		scalars.append(scalar)
	}

	return ok(text_of(scalars))
}

// Encodes text as ISO-8859-1, one byte per scalar. A scalar above U+00FF returns
// `EBADMSG`.
export fn latin1_encode(text String) Bytes! {
	return narrow(text, 255)
}

fn narrow(text String, maximum Int) Bytes! {
	var out = BytesBuilder()

	for scalar in text.scalar_values() {
		if scalar > maximum { return error(encoding_invalid_data()) }

		out.append(byte_of(scalar))
	}

	return ok(out.build())
}

// Decodes ISO-8859-1 bytes, mapping every byte to the scalar of the same value.
export fn latin1_decode(data Bytes) String {
	return text_of(data.values().map(b => b.to_int()))
}

// Encodes text as 7-bit ASCII. A scalar above U+007F returns `EBADMSG`.
export fn ascii_encode(text String) Bytes! {
	return narrow(text, 127)
}

// Decodes 7-bit ASCII bytes. A byte above 0x7F returns `EBADMSG`.
export fn ascii_decode(data Bytes) String! {
	bytes := data.values()
	for byte in bytes {
		if byte > 127 { return error(encoding_invalid_data()) }
	}
	return ok(data.decode_utf8() or "")
}

// A table value known to be a digit, with its range visible to the checker of
// arithmetic.
fn masked(digit Int) Int {
	return msrt_bits_bit_and(digit, 127)
}

fn min_of(a, b Int) Int {
	if a < b { return a }
	return b
}

fn is_negative(max_bytes Int?) Bool {
	limit := max_bytes
	return limit != null and limit < 0
}

fn invalid_input[T]() T! {
	return error(Error("encoding: invalid input", kind: "EINVAL"))
}

fn invalid_data[T]() T! {
	return error(Error("encoding: invalid data", kind: "EBADMSG"))
}

fn limit_exceeded[T]() T! {
	return error(Error("encoding: limit exceeded", kind: "EOVERFLOW"))
}

BASE32_SYMBOLS List[UInt8] := [
	65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85,
	86, 87, 88, 89, 90, 50, 51, 52, 53, 54, 55
]
BASE32_HEX_SYMBOLS List[UInt8] := [
	48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75,
	76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86
]
HEX_SYMBOLS List[UInt8] := [
	48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102
]
BASE32_VALUES List[Int] := [
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 26,
	27, 28, 29, 30, 31, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 1, 2, 3, 4, 5,
	6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
]
BASE32_HEX_VALUES List[Int] := [
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 1, 2, 3, 4,
	5, 6, 7, 8, 9, 255, 255, 255, 255, 255, 255, 255, 10, 11, 12, 13, 14, 15, 16, 17,
	18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
]
HEX_VALUES List[Int] := [
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0, 1, 2, 3, 4,
	5, 6, 7, 8, 9, 255, 255, 255, 255, 255, 255, 255, 10, 11, 12, 13, 14, 15, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 10, 11, 12, 13, 14, 15, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
]
ASCII85_VALUES List[Int] := [
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 0,
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
	24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44,
	45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65,
	66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
	255
]

fn encoding_invalid_data() Error {
	return Error("encoding: invalid data", kind: "EBADMSG")
}
