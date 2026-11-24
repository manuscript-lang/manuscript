// Wraps text in double quotes and escapes it the way JSON does. A control character
// below U+0020 gets its short JSON escape where one exists, otherwise \uXXXX. U+007F is
// always escaped as \uXXXX. Pass `escape_c1: true` to escape U+0080 to U+009F too.
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

	var result = ""
	result += "\""

	for c in text.chars():
		code := c.scalar_at(0)

		if c == "\"": result += "\\\""
		else if c == "\\": result += "\\\\"
		else if c == "\n": result += "\\n"
		else if c == "\t": result += "\\t"
		else if c == "\r": result += "\\r"
		else if code == 8: result += "\\b"
		else if code == 12: result += "\\f"
		else if code < 32 or code == 127 or (escape_c1 and code >= 128 and code <= 159):
			result += "\\u"
			result += hex4(code)
		else: result += c

	result += "\""
	return result

// Four lowercase hex digits for a code unit, zero padded.
fn hex4(code: Int) String:
	return code.to_hex().pad_start(4, "0")
