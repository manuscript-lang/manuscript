// Small helpers for building and reading JsonValue documents.
import JsonValue, stringify, parse from "@std/data/json.ms"

export fn str(value: String) JsonValue:
	return JsonValue.StringValue(value.clone())

export fn num(value: Int) JsonValue:
	return JsonValue.NumberValue("{value}")

export fn flag(value: Bool) JsonValue:
	return JsonValue.BoolValue(value)

export fn arr(values: List[JsonValue]) JsonValue:
	return JsonValue.ArrayValue(values)

export fn obj(values: Map[String, JsonValue]) JsonValue:
	return JsonValue.ObjectValue(values)

// Reads `key` as a string, or `fallback` when absent or not a string.
export fn str_or(doc: JsonValue, key: String, fallback: String) String:
	if field := doc.get(key):
		if text := field.as_string(): return text
	return fallback.clone()

export fn int_or(doc: JsonValue, key: String, fallback: Int) Int:
	if field := doc.get(key):
		if n := field.as_int(): return n
	return fallback.clone()

export fn render(doc: JsonValue) String!:
	return stringify(doc)

export fn read(text: String) JsonValue!:
	return parse(text)

export fn flag_or(doc: JsonValue, key: String, fallback: Bool) Bool:
	if field := doc.get(key):
		if on := field.as_bool(): return on
	return fallback
