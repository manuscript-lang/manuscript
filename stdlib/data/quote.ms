import StringBuilder from "@std/string_builder.ms"

// Double-quotes text with JSON-style escapes. Controls below U+0020 use a short JSON
// escape where available, otherwise \uXXXX. U+007F is always escaped as \uXXXX;
// `escape_c1` also escapes U+0080 to U+009F.
export fn quote_text(text: String, escape_c1: Bool) String:
	var clean = true

	for code in text.scalar_values():
		if (
			code < 32
			or code == 34
			or code == 92
			or code == 127
			or (escape_c1 and code >= 128 and code <= 159)
		):
			clean = false
			break

	if clean: return "\"".concat(text).concat("\"")

	var result = StringBuilder()
	result.append("\"")

	for c in text.chars():
		code := c.scalar_at(0)

		if c == "\"": result.append("\\\"")
		else if c == "\\": result.append("\\\\")
		else if c == "\n": result.append("\\n")
		else if c == "\t": result.append("\\t")
		else if c == "\r": result.append("\\r")
		else if code == 8: result.append("\\b")
		else if code == 12: result.append("\\f")
		else if code < 32 or code == 127 or (escape_c1 and code >= 128 and code <= 159):
			result.append("\\u")
			result.append(hex4(code))
		else: result.append(c)

	result.append("\"")
	return result.build()

// Four lowercase hex digits for a code unit, zero padded.
fn hex4(code: Int) String:
	return code.to_string_radix(16).pad_start(4, "0")
