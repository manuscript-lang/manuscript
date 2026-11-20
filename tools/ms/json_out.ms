// The `--json` documents of the commands: two-space indented, one trailing newline, and
// `<`, `>`, `&`, U+2028 and U+2029 escaped so a document can sit in HTML.
import (
	JsonValue, StringifyOptions, stringify from "@std/data/json.ms",
	expect_equal from "@std/test/test.ms",
)

export fn object() JsonValue:
	return JsonValue.ObjectValue(Map[String, JsonValue]())

export fn text(value: String) JsonValue:
	return JsonValue.StringValue(value.clone())

export fn number(value: Int) JsonValue:
	return JsonValue.NumberValue(f"{value}")

export fn flag(value: Bool) JsonValue:
	return JsonValue.BoolValue(value)

export fn list_of(items: List[JsonValue]) JsonValue:
	return JsonValue.ArrayValue(items)

// `members` with `key` set to `value`, placed last when new.
export fn with(members: JsonValue, key: String, value: JsonValue) JsonValue:
	match members:
		ObjectValue(values):
			var next = values.clone()
			next.add(key, value)
			return JsonValue.ObjectValue(next)
		_: return members.clone()

fn html_safe(encoded: String) String:
	return encoded.replace("<", "\\u003c").replace(">", "\\u003e").replace(
		"&",
		"\\u0026",
	).replace("\u{2028}", "\\u2028").replace("\u{2029}", "\\u2029")

// The text of `value`.
export fn render_document(value: JsonValue) String:
	return html_safe(stringify(value, StringifyOptions(indent: 2)).get_or("")) + "\n"

// The single-line text of `value`, without spaces, safe inside an HTML script element.
export fn render_compact(value: JsonValue) String:
	return html_safe(stringify(value, StringifyOptions()).get_or(""))

test "markup characters are escaped":
	text := render_document(JsonValue.StringValue("a<b>&c\u{8}\u{c}\u{7f}"))
	expect_equal(text, "\"a\\u003cb\\u003e\\u0026c\\b\\f\u{7f}\"\n")?
