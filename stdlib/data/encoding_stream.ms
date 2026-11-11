import (
	Bytes, join from "@std/bytes.ms",
	base64_decode, base64_encode, hex_decode, hex_encode from "@std/data/encoding.ms",
	ReadStream, Transform, through from "@std/io/io.ms",
)

// Stream steps for `@std/data/encoding.ms`, in their own module because the streams
// depend on `@std/bytes.ms`, which `encoding.ms` must not import. Each step carries
// only the few bytes or characters that do not yet fill a group.

// Encodes bytes in groups of three, so a chunk boundary never splits a Base64 group.
type Base64Encoding:
	url_safe: Bool
	tail: Bytes

fn var Base64Encoding.step(value: Bytes, var out: List[String]) Unit!:
	data := self.tail.concat(value)
	whole := data.length() - data.length() % 3
	self.tail = data.slice(whole, data.length())?
	if whole == 0: return ok(unit)

	out.append(base64_encode(data.slice(0, whole)?, self.url_safe))

fn var Base64Encoding.finish(var out: List[String]) Unit!:
	if self.tail.is_empty(): return ok(unit)

	last := self.tail.clone()
	self.tail = join([])
	out.append(base64_encode(last, self.url_safe))

// Encodes a byte stream as Base64 text chunks that concatenate to the whole encoding,
// with padding at the end. Set `url_safe: true` for the URL-safe alphabet. Closing the
// result closes `input`.
export fn base64_encoded(
	input: ReadStream[Bytes],
	url_safe: Bool = false,
) ReadStream[String]:
	return through[Bytes, String](
		input,
		Base64Encoding(url_safe: url_safe, tail: join([])),
	)

// Decodes Base64 text in groups of four characters, so a chunk boundary never splits a
// group.
type Base64Decoding:
	url_safe: Bool
	tail: String
	ended: Bool = false

fn var Base64Decoding.step(value: String, var out: List[Bytes]) Unit!:
	if self.ended and not value.is_empty(): return error(
		Error("encoding: invalid data", kind: "EBADMSG")
	)

	text := self.tail.concat(value)
	whole := text.length() - text.length() % 4
	self.tail = text.slice(whole, text.length()).get("")
	if whole == 0: return ok(unit)

	part := text.slice(0, whole).get("")
	decoded := base64_decode(part, self.url_safe)?

	// Every complete group decodes to three bytes unless the last group has
	// padding.
	if decoded.length() != whole / 4 * 3:
		self.ended = true

		if not self.tail.is_empty():
			self.tail = ""
			return error(Error("encoding: invalid data", kind: "EBADMSG"))

	out.append(decoded)

fn var Base64Decoding.finish(var out: List[Bytes]) Unit!:
	last := self.tail.clone()
	self.tail = ""
	if last == "": return ok(unit)

	out.append(base64_decode(last, self.url_safe)?)

// Decodes Base64 text chunks into bytes. Malformed text fails the read with `EBADMSG`;
// text that ends inside a group fails at the end of the stream. Closing the result
// closes `input`.
export fn base64_decoded(
	input: ReadStream[String],
	url_safe: Bool = false,
) ReadStream[Bytes]:
	return through[String, Bytes](input, Base64Decoding(url_safe: url_safe, tail: ""))

type HexEncoding:
	unused: Int

fn var HexEncoding.step(value: Bytes, var out: List[String]) Unit!:
	out.append(hex_encode(value))

fn var HexEncoding.finish(var out: List[String]) Unit!:
	return ok(unit)

// Encodes a byte stream as lowercase hexadecimal text chunks. Closing the result closes
// `input`.
export fn hex_encoded(input: ReadStream[Bytes]) ReadStream[String]:
	return through[Bytes, String](input, HexEncoding(0))

// Decodes hexadecimal text in pairs, so a chunk boundary never splits a byte.
type HexDecoding:
	tail: String

fn var HexDecoding.step(value: String, var out: List[Bytes]) Unit!:
	text := self.tail.concat(value)
	whole := text.length() - text.length() % 2
	self.tail = text.slice(whole, text.length()).get("")
	if whole == 0: return ok(unit)

	out.append(hex_decode(text.slice(0, whole).get(""))?)

fn var HexDecoding.finish(var out: List[Bytes]) Unit!:
	last := self.tail.clone()
	self.tail = ""
	if last == "": return ok(unit)

	out.append(hex_decode(last)?)

// Decodes hexadecimal text chunks into bytes. Malformed text, or text that ends inside
// a pair, fails the read with `EBADMSG`. Closing the result closes `input`.
export fn hex_decoded(input: ReadStream[String]) ReadStream[Bytes]:
	return through[String, Bytes](input, HexDecoding(tail: ""))
