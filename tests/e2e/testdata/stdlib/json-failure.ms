import (
	JsonOptions, JsonValue, parse from "@std/data/json.ms",
	expect_contains, expect_equal, expect_error from "@std/test/test.ms",
)

fn expect_syntax_error[T](actual: T!) Unit!:
	cause := expect_error(actual)?
	expect_equal(cause.kind, "EBADMSG")?
	expect_contains(cause.message, "JSON: invalid data: line ")?

test "JSON syntax errors keep their identity with unread Unicode suffixes":
	for text in [
		"]plain", "]\\\\", "]\"\\u0041\"", "]\"\\uD800\"", "]\"\\u12",
		"true x\"\\uD800\""
	]:
		expect_syntax_error(parse(text))?
		expect_syntax_error(parse[String](text))?

test "JSON value limits preserve Unicode precedence and byte admission":
	limited: JsonValue! := error(Error("JSON: limit exceeded", kind: "EOVERFLOW"))
	typed_limited: String! := error(Error("JSON: limit exceeded", kind: "EOVERFLOW"))
	zero := JsonOptions(max_values: 0)

	for text in ["\"\\uD800\"", "\"\\uDC00\"", "\"\\u12"]:
		expect_syntax_error(parse(text, zero))?
		expect_syntax_error(parse[String](text, zero))?

	expect_equal(parse("\"\\u0041\"", zero), limited)?
	expect_equal(parse[String]("\"\\u0041\"", zero), typed_limited)?
	expect_equal(parse("\"\\uD800\"", JsonOptions(max_bytes: 0)), limited)?
	expect_equal(parse[String]("\"\\uD800\"", JsonOptions(max_bytes: 0)), typed_limited)?

	negative: JsonValue! := error(Error("JSON: invalid input", kind: "EINVAL"))
	typed_negative: String! := error(Error("JSON: invalid input", kind: "EINVAL"))
	expect_equal(parse("\"\\uD800\"", JsonOptions(max_values: -1)), negative)?
	expect_equal(
		parse[String]("\"\\uD800\"", JsonOptions(max_values: -1)), typed_negative
	)?
