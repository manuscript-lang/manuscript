// JSON round trip on a generic document: build text, parse into a value tree, walk it,
// stringify it back.
import (
	JsonValue, parse, stringify from "@std/data/json.ms",
	StringBuilder from "@std/string_builder.ms",
)

fn lcg(x: Int) Int:
	return (x * 1103515245 + 12345) % 2147483648

// Keys are in sorted order so every language writes members the same way.
fn make_text(n: Int) String:
	var sb = StringBuilder()
	var x = 1
	sb.append("[")

	for i in 0..n:
		x = lcg(x)
		if i > 0: sb.append(",")
		sb.append(
			"\{\"id\":{i},\"name\":\"item-{x % 1000}\",\"score\":{x / 7 % 10000},\"tags\":[\"t{x % 7}\",\"t{x % 11}\"],\"nested\":\{\"a\":{x % 5},\"b\":[{x % 3},{x % 13}]\}\}"
		)

	sb.append("]")
	return sb.build()

fn walk(v: JsonValue) Int:
	match v:
		Null: return 1
		BoolValue(_): return 1
		NumberValue(t): return t.parse_int().get(0)
		StringValue(s): return s.length()
		ArrayValue(items):
			var t = 0
			for item in items:
				t += walk(item)
			return t
		ObjectValue(members):
			var t = 0
			for e in members.entries():
				t += e.key.length() + walk(e.value)
			return t

fn main() Unit:
	text := make_text(120000)
	var total = 0
	var out_len = 0

	for pass in 0..3:
		doc := parse[JsonValue](text).get()
		total += walk(doc)
		out_len += stringify(doc).get("").length()

	print("text {text.length()} walk {total} out {out_len}")
