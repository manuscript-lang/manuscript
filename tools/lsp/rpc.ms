// JSON-RPC message building and the small readers the server needs over `JsonValue`.
import JsonValue, stringify from "@std/data/json.ms"

export type Field:
	key: String
	value: JsonValue

export fn object(fields: List[Field]) JsonValue:
	var values = Map[String, JsonValue]()
	for field in fields:
		values.add(field.key.clone(), field.value.clone())
	return JsonValue.ObjectValue(values)

export fn json_text(value: String) JsonValue: JsonValue.StringValue(value.clone())

export fn number(value: Int) JsonValue: JsonValue.NumberValue(f"{value}")

export fn list(values: List[JsonValue]) JsonValue: JsonValue.ArrayValue(values.clone())

export fn field(key: String, value: JsonValue) Field: Field(
	key: key.clone(),
	value: value.clone(),
)

// A response carrying `result` for request `id`.
export fn result_message(id: JsonValue, result: JsonValue) String:
	return stringify(
		object(
			[
				field("jsonrpc", json_text("2.0")),
				field("id", id),
				field("result", result),
			]
		)
	).get_or("")

// An error response; `id` is `Null` when the request could not be read.
export fn error_message(id: JsonValue, code: Int, message: String) String:
	failure := object(
		[field("code", number(code)), field("message", json_text(message))]
	)
	return stringify(
		object(
			[
				field("jsonrpc", json_text("2.0")),
				field("id", id),
				field("error", failure),
			]
		)
	).get_or("")

// A server notification.
export fn notification(method: String, params: JsonValue) String:
	return stringify(
		object(
			[
				field("jsonrpc", json_text("2.0")),
				field("method", json_text(method)),
				field("params", params),
			]
		)
	).get_or("")

// The string at `keys` in `value`, or "".
export fn string_at(value: JsonValue, keys: List[String]) String:
	if found := value.get_in(keys): return found.as_string().get_or("")
	return ""

// The integer at `keys` in `value`, or `fallback`.
export fn int_at(value: JsonValue, keys: List[String], fallback: Int) Int:
	if found := value.get_in(keys): return found.as_int().get_or(fallback)
	return fallback
