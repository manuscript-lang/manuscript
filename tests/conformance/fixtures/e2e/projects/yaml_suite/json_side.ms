import (
	JsonValue, parse from "@std/data/json.ms",
	from_scalars from "@std/string.ms",
)

// The canonical texts of the JSON values in a stream of whitespace-separated values:
// numbers by value, object members sorted.
export fn canon_json_stream(text String) List[String]!:
	var out List[String] = []
	for item in split_values(text):
		out.append(canon(parse(item)?))
	return ok(out)

// The top-level values of a JSON stream, found by tracking depth and strings.
fn split_values(text String) List[String]:
	var values List[String] = []
	var current = ""
	var depth = 0
	var in_string = false
	var escaped = false
	var started = false

	for code in text.scalar_values():
		ch := from_scalars([code]).get_or("")
		spacing := code == 32 or code == 9 or code == 10 or code == 13

		if in_string:
			current += ch

			if escaped: escaped = false
			else if code == 92: escaped = true
			else if code == 34:
				in_string = false

				if depth == 0:
					values.append(current)
					current = ""
					started = false

			continue

		if depth == 0 and spacing:
			if started:
				values.append(current)
				current = ""
				started = false

			continue

		started = true
		current += ch

		if code == 34: in_string = true
		else if code == 91 or code == 123: depth += 1
		else if code == 93 or code == 125:
			depth -= 1

			if depth == 0:
				values.append(current)
				current = ""
				started = false

	if started: values.append(current)
	return values

fn canon(value JsonValue) String:
	match value:
		Null: return "n"
		BoolValue(flag): return if flag: "t" else: "f"
		NumberValue(text): return f"N{(text.parse_float() or 0.0)}"
		StringValue(text): return f"s{text.length()}:{text}"
		ArrayValue(items):
			var parts List[String] = []
			for item in items:
				parts.append(canon(item))
			return f"[{parts.join(",")}]"
		ObjectValue(members):
			var parts List[String] = []
			for entry in members.entries():
				parts.append(f"{entry.key.length()}:{entry.key}={canon(entry.value)}")
			parts.sort()
			return f"\{{parts.join(",")}\}"
