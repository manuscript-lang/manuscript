// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn pad(n: Int) String:
	return "x".repeat(n)

test "trim keeps text with no outer whitespace in every string form":
	expect_equal("abc".trim(), "abc")?
	expect_equal(pad(40).trim(), pad(40))?
	expect_equal("".trim(), "")?
	expect_equal("é".trim(), "é")?

test "trim removes ASCII whitespace from either end":
	expect_equal(" a".trim(), "a")?
	expect_equal("a\n".trim(), "a")?
	expect_equal(" \t\r\n ".trim(), "")?
	expect_equal(" ".trim(), "")?
	expect_equal(("  " + pad(30) + " ").trim(), pad(30))?
	expect_equal(" a b ".trim_start(), "a b ")?
	expect_equal(" a b ".trim_end(), " a b")?
	expect_equal("a ".trim_start(), "a ")?
	expect_equal(" a".trim_end(), " a")?

test "trim handles Unicode whitespace and mixed ends":
	expect_equal("\u{2003}é\u{2003}".trim(), "é")?
	expect_equal("é ".trim(), "é")?
	expect_equal(" é".trim(), "é")?
