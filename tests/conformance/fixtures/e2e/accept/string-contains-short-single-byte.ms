// conform: tags=testing,strings,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn operator(c: String) Bool:
	return "+-*/".contains(c)

test "a one-byte needle in a short text":
	expect_equal(operator("*"), true)?
	expect_equal(operator("x"), false)?
	expect_equal("".contains("a"), false)?

test "empty, multi-byte and longer needles":
	long := "abcdefghijklmnopqrstuvwxyz0123456789"
	expect_equal(operator(""), true)?
	expect_equal(operator("+-"), true)?
	expect_equal(operator("-+"), false)?
	expect_equal(long.contains("9"), true)?
	expect_equal(long.contains("A"), false)?
	expect_equal(long.contains("xyz0"), true)?
	expect_equal(long.contains(""), true)?
	expect_equal("é".contains("é"), true)?
	expect_equal("aé".contains("a"), true)?
	expect_equal("aé".contains("b"), false)?

test "text of exactly 31 and 32 bytes":
	t31 := "a".repeat(30).get("") + "z"
	t32 := "a".repeat(31).get("") + "z"
	expect_equal(t31.contains("z"), true)?
	expect_equal(t32.contains("z"), true)?
	expect_equal(t31.contains("y"), false)?
	expect_equal(t32.contains("y"), false)?
