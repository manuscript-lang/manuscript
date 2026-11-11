import (
	expect_equal, expect_true from "@std/test/test.ms",
	parse_int from "@std/math/math.ms",
)

fn double(text: String) Int!:
	value := parse_int(text, 10)?
	return ok(value * 2)

fn label(text: String) String!:
	return ok(text | double? | stringify)

fn stringify(value: Int) String:
	return "n={value}"

fn check_positive(value: Int) Unit!:
	if value < 0: return error(Error("negative"))

fn both(text: String) Int!:
	value := parse_int(text, 10)?
	check_positive(value)?
	return ok(value)

test "postfix ? propagates like try":
	expect_equal(double("21")?, 42)?
	expect_equal(label("4")?, "n=8")?
	expect_true(double("x").is_error())?
	expect_true(both("-1").is_error())?
	expect_equal(both("3")?, 3)?
