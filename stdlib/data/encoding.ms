import (
	Bytes, BytesBuilder from "@std/bytes.ms",
	from_scalars from "@std/string.ms",
	StringBuilder from "@std/string_builder.ms",

	msstd_encoding_ascii85_decode,
	msstd_encoding_ascii85_encode,
	msstd_encoding_base32_decode,
	msstd_encoding_base32_encode,
	msstd_encoding_base64_decode,
	msstd_encoding_base64_decode_unpadded,
	msstd_encoding_base64_encode_unpadded,
	msstd_encoding_hex_decode,
	msstd_encoding_hex_encode from "@std/internal/encoding.ms",
)

// Encodes unframed ASCII85; complete groups of four zero bytes become `z`. No Adobe
// `<~`/`~>` delimiters are added. Example: `ascii85_encode("hello".to_bytes())` is
// `"BOu!rDZ"`.
export fn ascii85_encode(data: Bytes) String:
	return msstd_encoding_ascii85_encode(data)

/*
Decodes unframed ASCII85, ignoring ASCII bytes 0 through 32; `z` is valid only between groups.
Rejects Adobe delimiters, one-digit tails, invalid characters and overflowing complete or partial 32-bit groups.
Negative `max_bytes` returns EINVAL; decoded output above it returns EOVERFLOW before allocating output.
*/
export fn ascii85_decode(text: String, max_bytes: Int?) Bytes!:
	return msstd_encoding_ascii85_decode(text, max_bytes)

// Alphabet and padding for `base32_encode` and `base32_decode`.
export type Base32Options:
	// True selects the extended hex alphabet 0-9/A-V.
	hex_alphabet: Bool = false
	// False omits (or forbids) the `=` padding.
	padded: Bool = true

// Encodes uppercase RFC 4648 Base32, using the alphabet and padding in `options`.
// Example: `base32_encode("f".to_bytes())` returns `"MY======"`.
export fn base32_encode(data: Bytes, options: Base32Options = Base32Options()) String:
	return msstd_encoding_base32_encode(data, options.hex_alphabet, options.padded)

/*
Decodes uppercase RFC 4648 Base32, or 0-9/A-V when `options.hex_alphabet` is true.
Padding must be exact and only at the end; `padded: false` forbids `=`. Whitespace and nonzero unused bits return EBADMSG.
Negative `max_bytes` returns EINVAL; output exceeding it returns EOVERFLOW.
*/
export fn base32_decode(
	text: String,
	options: Base32Options = Base32Options(),
	max_bytes: Int? = none,
) Bytes!:
	return msstd_encoding_base32_decode(
		text,
		options.hex_alphabet,
		options.padded,
		max_bytes,
	)

/*
Decodes standard Base64 by default; set `url_safe: true` for the URL-safe alphabet.
`padded: false` expects text without `=` and rejects it, whitespace and nonzero unused bits.
*/
export fn base64_decode(
	text: String,
	url_safe: Bool = false,
	max_bytes: Int?,
	padded: Bool = true,
) Bytes!:
	if not padded: return msstd_encoding_base64_decode_unpadded(
		text,
		url_safe,
		max_bytes,
	)
	return msstd_encoding_base64_decode(text, url_safe, max_bytes)

// The budget as a count, with no budget as a very large one and a negative budget as
// -1.
fn budget(max_bytes: Int?) Int:
	if limit := max_bytes: return limit
	return 9223372036854775807

// Encodes bytes as standard Base64 by default; set `url_safe: true` for URL-safe text
// and `padded: false` to omit `=`. Example:
// `base64_encode("f".to_bytes(), padded: false)` returns `"Zg"`.
export fn base64_encode(data: Bytes, url_safe: Bool = false, padded: Bool = true) String:
	if not padded: return msstd_encoding_base64_encode_unpadded(data, url_safe)
	if data.is_empty(): return ""

	text := msstd_encoding_base64_encode_unpadded(data, url_safe)
	tail := data.length() % 3
	if tail == 1: return text + "=="
	if tail == 2: return text + "="

	return text

// Decodes hexadecimal text. `max_bytes` bounds decoded output when supplied.
export fn hex_decode(text: String, max_bytes: Int?) Bytes!:
	return msstd_encoding_hex_decode(text, max_bytes)

// Encodes each byte as two lowercase hexadecimal digits.
export fn hex_encode(data: Bytes) String:
	return msstd_encoding_hex_encode(data)

// Encodes text as UTF-16 code units, little-endian unless `little_endian` is false.
// No byte order mark is written.
export fn utf16_encode(text: String, little_endian: Bool = true) Bytes:
	var out = BytesBuilder()

	for scalar in text.scalar_values():
		if scalar < 65536:
			append_unit(var out, scalar, little_endian)
		else:
			offset := scalar - 65536
			append_unit(var out, 55296 + offset / 1024, little_endian)
			append_unit(var out, 56320 + offset % 1024, little_endian)

	return out.build()

fn append_unit(var out: BytesBuilder, code: Int, little_endian: Bool) Unit:
	if little_endian:
		out.append(byte_of(code % 256))
		out.append(byte_of(code / 256))
	else:
		out.append(byte_of(code / 256))
		out.append(byte_of(code % 256))

// UTF-8 byte length of one scalar.
fn utf8_length(scalar: Int) Int:
	if scalar < 128: return 1
	if scalar < 2048: return 2
	if scalar < 65536: return 3

	return 4

// A byte from a count already known to be 0 through 255.
fn byte_of(n: Int) UInt8:
	return n.to_uint8().get(0)

fn text_of(scalars: List[Int]) String:
	if text := from_scalars(scalars): return text
	return ""

// Decodes UTF-16 bytes, little-endian unless `little_endian` is false. An odd length or
// an unpaired surrogate returns EBADMSG; a negative `max_bytes` returns EINVAL, and
// decoded text longer than `max_bytes` UTF-8 bytes returns EOVERFLOW.
export fn utf16_decode(data: Bytes, little_endian: Bool = true, max_bytes: Int?) String!:
	limit := budget(max_bytes)
	if limit < 0: return error(Error("encoding: invalid input", kind: "EINVAL"))

	bytes := data.values()
	if bytes.length() % 2 != 0: return error(encoding_invalid_data())

	var units = List[Int]()

	for pair in 0..(bytes.length() / 2):
		low := bytes[pair * 2].to_int()
		high := bytes[pair * 2 + 1].to_int()

		if little_endian: units.append(low + high * 256)
		else: units.append(low * 256 + high)

	var scalars = List[Int]()
	var size = 0
	var index = 0

	while index < units.length():
		code := units[index]
		var scalar = code
		index += 1
		if code >= 56320 and code < 57344: return error(encoding_invalid_data())

		if code >= 55296 and code < 56320:
			if index >= units.length(): return error(encoding_invalid_data())

			next := units[index]
			if next < 56320 or next >= 57344: return error(encoding_invalid_data())

			scalar = 65536 + (code - 55296) * 1024 + (next - 56320)
			index += 1

		size += utf8_length(scalar)
		if size > limit: return error(
			Error("encoding: limit exceeded", kind: "EOVERFLOW")
		)

		scalars.append(scalar)

	return ok(text_of(scalars))

// Encodes text as ISO-8859-1, one byte per scalar. A scalar above U+00FF returns
// EBADMSG.
export fn latin1_encode(text: String) Bytes!:
	return narrow(text, 255)

fn narrow(text: String, maximum: Int) Bytes!:
	var out = BytesBuilder()

	for scalar in text.scalar_values():
		if scalar > maximum: return error(encoding_invalid_data())

		out.append(byte_of(scalar))

	return ok(out.build())

// Decodes ISO-8859-1 bytes, mapping every byte to the scalar of the same value.
export fn latin1_decode(data: Bytes) String:
	return text_of(data.values().map(fn b: b.to_int()))

// Encodes text as 7-bit ASCII. A scalar above U+007F returns EBADMSG.
export fn ascii_encode(text: String) Bytes!:
	return narrow(text, 127)

// Decodes 7-bit ASCII bytes. A byte above 0x7F returns EBADMSG.
export fn ascii_decode(data: Bytes) String!:
	bytes := data.values()
	for byte in bytes:
		if byte > 127: return error(encoding_invalid_data())
	return ok(data.decode_utf8().get(""))

fn encoding_invalid_data() Error:
	return Error("encoding: invalid data", kind: "EBADMSG")
