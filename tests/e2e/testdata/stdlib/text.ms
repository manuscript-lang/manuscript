import (
	parse_int from "@std/math/math.ms",
	from_scalars from "@std/string.ms",
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",
	parse_bool, quote, quote_ascii, unquote from "@std/text.ms",
)

test "text conversions and quoting":
	parse_bool("YES") | expect_equal(true)?
	parse_bool("x") | expect_equal(none)?
	quote("a\"b\n") | expect_equal("\"a\\\"b\\n\"")?
	quote_ascii("é🙂") | expect_equal("\"\\u\{e9\}\\u\{1f642\}\"")?
	(
		unquote("\"a\\tb\\u\{e9\}\"")
		| expect_ok?
		| expect_equal("a\tbé")?
	)
	(
		unquote("abc") | expect_error? | expect_equal(
			Error("string: invalid input", kind: "EINVAL")
		)?
	)
	(
		unquote("\"a\"b\"") | expect_error? | expect_equal(
			Error("string: invalid input", kind: "EINVAL")
		)?
	)
	(
		unquote("\"\\q\"") | expect_error? | expect_equal(
			Error("string: invalid input", kind: "EINVAL")
		)?
	)
	(
		unquote("\"\\u\{d800\}\"") | expect_error? | expect_equal(
			Error("string: invalid input", kind: "EINVAL")
		)?
	)
	(
		unquote(
			quote("tab\there \"q\" \\ é🙂\u{1}")
		) | expect_ok? | expect_equal("tab\there \"q\" \\ é🙂\u{1}")?
	)

test "parse_int radix 0 reads a prefix and others reject it":
	text := "-0x1f"
	expect_equal(parse_int(text, 0)?, -31)?
	expect_equal(parse_int("0b101", 0)?, 5)?
	expect_equal(parse_int("-ff", 16)?, -255)?
	expect_equal(parse_int("+ff", 16)?, 255)?
	expect_equal(parse_int("-9223372036854775808", 10)?, -9223372036854775807 - 1)?
	expect_equal(parse_int(text, 16).is_error(), true)?
	expect_equal(parse_int(text, 10).is_error(), true)?
	expect_equal(parse_int("-", 10).is_error(), true)?
	expect_equal(parse_int("0x", 0).is_error(), true)?
	expect_equal(parse_int("9223372036854775808", 10).is_error(), true)?
	expect_equal(parse_int("12", 2).is_error(), true)?

test "text quoting escapes interpolation braces and literal controls":
	quote("\{x\}") | expect_equal("\"\\\{x\\\}\"")?
	(
		unquote("\"\\\{x\\\}\"")
		| expect_ok?
		| expect_equal("\{x\}")?
	)
	quote("\}") | expect_equal("\"\\\}\"")?
	(
		unquote("\"\\\}\"")
		| expect_ok?
		| expect_equal("\}")?
	)
	quote("\\u\{41\}") | expect_equal("\"\\\\u\\\{41\\\}\"")?
	(
		unquote("\"\\\\u\\\{41\\\}\"")
		| expect_ok?
		| expect_equal("\\u\{41\}")?
	)

	for scalar in [0, 31, 127, 128, 133, 159, 8232, 8233, 8234, 8238, 8294, 8297]:
		text := from_scalars([scalar])?
		expected := "\"\\u\{" + scalar.to_string_radix(16) + "\}\""
		quote(text) | expect_equal(expected)?
		(
			unquote(quote(text))
			| expect_ok?
			| expect_equal(text)?
		)

test "text Unicode escapes reject signs nonhex digits and excess width":
	for text in [
		"\"\\u\{\}\"", "\"\\u\{+41\}\"", "\"\\u\{-0\}\"", "\"\\u\{ 41\}\"",
		"\"\\u\{41 \}\"", "\"\\u\{0x41\}\"", "\"\\u\{0000000\}\"",
		"\"\\u\{00000041\}\"", "\"\\u\{g\}\"", "\"\\u\{d800\}\"", "\"\\u\{110000\}\"",
		"\"\\u\{ffffffffffffffff\}\""
	]:
		(
			unquote(text)
			| expect_error?
			| expect_equal(Error("string: invalid input", kind: "EINVAL"))?
		)

test "text Unicode escapes preserve scalar boundaries and leading zeros":
	(
		unquote("\"\\u\{000000\}\"")
		| expect_ok?
		| expect_equal(from_scalars([0])?)?
	)
	(unquote("\"\\u\{000041\}\"") | expect_ok? | expect_equal(from_scalars([65])?)?)
	(unquote("\"\\u\{d7ff\}\"") | expect_ok? | expect_equal(from_scalars([55295])?)?)
	(unquote("\"\\u\{E000\}\"") | expect_ok? | expect_equal(from_scalars([57344])?)?)
	(
		unquote("\"\\u\{10FFFF\}\"") | expect_ok? | expect_equal(
			from_scalars([1114111])?
		)?
	)

test "text quoting round trips scalar and escape neighbors":
	for scalar in [
		0, 9, 10, 13, 31, 32, 34, 92, 123, 125, 127, 128, 159, 233, 2047, 2048, 8234,
		8297, 55295, 57344, 65535, 65536, 1114111
	]:
		text := "prefix " + (from_scalars([scalar])?) + " suffix"
		(
			unquote(quote(text))
			| expect_ok?
			| expect_equal(text)?
		)

		ascii := quote_ascii(text)
		for value in ascii.scalar_values():
			(value < 128) | expect_equal(true)?
		(
			unquote(ascii)
			| expect_ok?
			| expect_equal(text)?
		)
