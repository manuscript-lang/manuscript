import (
	Bytes from "@std/bytes.ms",
	ReadStream from "@std/io/io.ms",
	parse_int from "@std/math/math.ms",
	from_scalars from "@std/string.ms",
	StringBuilder from "@std/string_builder.ms",
)

/*
Conversions between text and values: booleans, integers in any base, and quoted literals.
Scalar classification lives in `@std/unicode.ms`; whole-string operations such as `fields_by`,
`trim_chars` and `title` are methods on String.

    import quote from "@std/text.ms"
    quote("a\tb")                  # a double-quoted literal with the escape written out
*/

// Parses `true`/`false` ignoring case, and `1`/`0`, `t`/`f`, `yes`/`no`, `on`/`off`;
// anything else is none.
export fn parse_bool(text: String) Bool?:
	word := text.trim().lower()
	if ["true", "t", "1", "yes", "on"].contains(word): return true
	if ["false", "f", "0", "no", "off"].contains(word): return false

	return none

/*
Quotes text as a double-quoted literal using the escapes of Manuscript string literals.
Printable Unicode stays as is; controls, bidi controls and U+2028/U+2029 become `\u{..}`.
Braces are escaped so the result stays literal instead of starting interpolation.
*/
export fn quote(text: String) String:
	return quote_with(text, false)

// Like quote, but every non-ASCII scalar is written as `\u{..}`, so the result is pure
// ASCII.
export fn quote_ascii(text: String) String:
	return quote_with(text, true)

fn quote_with(text: String, ascii_only: Bool) String:
	var out = StringBuilder()
	out.append("\"")

	for c in text.scalar_values():
		if c == 34:
			out.append("\\\"")
		else if c == 92:
			out.append("\\\\")
		else if c == 123 or c == 125:
			out.append("\\")
			out.append(from_scalars([c]).get(""))
		else if c == 10:
			out.append("\\n")
		else if c == 13:
			out.append("\\r")
		else if c == 9:
			out.append("\\t")
		else if (
			c < 32
			or (c >= 127 and c <= 159)
			or c == 8232
			or c == 8233
			or (c >= 8234 and c <= 8238)
			or (c >= 8294 and c <= 8297)
			or (ascii_only and c > 127)
		):
			out.append("\\u\{" + c.to_string_radix(16) + "\}")
		else:
			out.append(from_scalars([c]).get(""))

	out.append("\"")
	return out.build()

/*
Reverses quote: reads a double-quoted literal and returns its text. Supports `\"`, `\\`, `\n`,
`\r`, `\t`, `\0`, escaped braces and `\u{hex}` with 1 to 6 hexadecimal digits;
anything else, or text that is not fully quoted, is EINVAL.
*/
export fn unquote(text: String) String!:
	cs := text.scalar_values()
	if cs.length() < 2 or cs[0] != 34 or cs[cs.length() - 1] != 34:
		return error(Error("string: invalid input", kind: "EINVAL"))

	var out = List[Int]()
	var i = 1
	end := cs.length() - 1

	while i < end:
		c := cs[i]
		if c == 34: return error(Error("string: invalid input", kind: "EINVAL"))

		if c != 92:
			out.append(c)
			i += 1
		else if i + 1 >= end:
			return error(Error("string: invalid input", kind: "EINVAL"))
		else:
			e := cs[i + 1]
			i += 2

			if e == 110:
				out.append(10)
			else if e == 114:
				out.append(13)
			else if e == 116:
				out.append(9)
			else if e == 48:
				out.append(0)
			else if e == 34 or e == 92 or e == 123 or e == 125:
				out.append(e)
			else if e == 117 and i < end and cs[i] == 123:
				var j = i + 1
				var hex = List[Int]()

				while j < end and cs[j] != 125:
					digit := cs[j]
					if (
						hex.length() == 6
						or not (
							(digit >= 48 and digit <= 57)
							or (digit >= 65 and digit <= 70)
							or (
								digit >= 97
								and digit <= 102
							)
						)
					):
						return error(Error("string: invalid input", kind: "EINVAL"))

					hex.append(digit)
					j += 1

				if j >= end or hex.is_empty():
					return error(Error("string: invalid input", kind: "EINVAL"))

				digits := from_scalars(hex)?
				value := parse_int(digits, 16)
				if value.is_error():
					return error(Error("string: invalid input", kind: "EINVAL"))

				out.append(value.get(0))
				i = j + 1
			else:
				return error(Error("string: invalid input", kind: "EINVAL"))

	return from_scalars(out)

// Reads a string's scalars one at a time, decoding its UTF-8 bytes where it stands.
type ScalarSource:
	// The UTF-8 text, encoded once by `scalars`.
	bytes: Bytes
	// Byte offset of the next scalar, always on a scalar boundary.
	at: Int

// The next scalar as a one-scalar String, or none at the end.
fn var ScalarSource.next() String?!:
	if self.at >= self.bytes.length(): return ok(none)

	stop := self.at + scalar_width(self.bytes.get(self.at).to_int())
	scalar := self.bytes.decode_utf8_range(self.at, stop)
	self.at = stop
	return ok(scalar)

// Releases nothing; the bytes are owned by the source.
fn var ScalarSource.close() Unit!:
	return ok(unit)

// Bytes in the scalar a lead byte starts.
fn scalar_width(lead: Int) Int:
	if lead < 128: return 1
	if lead < 224: return 2
	if lead < 240: return 3

	return 4

// A stream of the text's scalars, each as a one-scalar String. Unlike `get(index)`,
// which walks from the start every time, the stream decodes the next scalar where it
// stopped, so scanning long non-ASCII text is linear.
export fn scalars(text: String) ReadStream[String]:
	return ReadStream[String](ScalarSource(text.to_bytes(), 0))
