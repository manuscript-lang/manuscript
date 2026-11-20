// Double-quoted text with Go `%q` escapes, as the Rust `quote` in ms-driver writes it.
import from_scalars from "@std/string.ms"

fn hex(value: Int, width: Int) String:
	digits := "0123456789abcdef"
	var out = ""
	var rest = value

	for _i in 0..width:
		out = digits.slice(rest % 16, rest % 16 + 1) + out
		rest /= 16

	return out

export fn quote(text: String) String:
	var out = "\""

	for code in text.scalar_values():
		if code == 34: out += "\\\""
		else if code == 92: out += "\\\\"
		else if code == 7: out += "\\a"
		else if code == 8: out += "\\b"
		else if code == 12: out += "\\f"
		else if code == 10: out += "\\n"
		else if code == 13: out += "\\r"
		else if code == 9: out += "\\t"
		else if code == 11: out += "\\v"
		else if code == 0xfffd: out += "\\ufffd"
		else if code < 0x20 or code == 0x7f: out += "\\x" + hex(code, 2)
		else if code >= 0x80 and code < 0xa0: out += "\\u" + hex(code, 4)
		else: out += from_scalars([code]).get_or("")

	return out + "\""
