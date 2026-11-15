import JsonValue, parse from "@std/data/json.ms"

// A canonical text for a JSON value: numbers by value, object members sorted.
export fn canon_json(text: String) String!:
	if text.trim() == "": return ok("n")
	return ok(canon(parse(text)?))

fn canon(value: JsonValue) String:
	match value:
		Null: return "n"
		BoolValue(flag): return if flag: "t" else: "f"
		NumberValue(text): return "N{text.parse_float().get(0.0)}"
		StringValue(text): return "s{text.length()}:{text}"
		ArrayValue(items):
			var parts: List[String] = []
			for item in items:
				parts.append(canon(item))
			return "[{parts.join(",")}]"
		ObjectValue(members):
			var parts: List[String] = []
			for entry in members.entries():
				parts.append("{entry.key.length()}:{entry.key}={canon(entry.value)}")
			parts.sort()
			return "\{{parts.join(",")}\}"
