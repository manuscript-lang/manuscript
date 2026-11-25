// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_true from "@std/test/test.ms"

fn pad(n Int) String {
	return "x".repeat(n)
}

test "trim keeps text with no outer whitespace in every string form" {
	expect_equal("abc".trim(), "abc")?
	expect_equal(pad(40).trim(), pad(40))?
	expect_equal("".trim(), "")?
	expect_equal("é".trim(), "é")?
}

test "trim removes ASCII whitespace from either end" {
	expect_equal(" a".trim(), "a")?
	expect_equal("a\n".trim(), "a")?
	expect_equal(" \t\r\n ".trim(), "")?
	expect_equal(" ".trim(), "")?
	expect_equal(("  " + pad(30) + " ").trim(), pad(30))?
	expect_equal(" a b ".trim_start(), "a b ")?
	expect_equal(" a b ".trim_end(), " a b")?
	expect_equal("a ".trim_start(), "a ")?
	expect_equal(" a".trim_end(), " a")?
}

test "trim handles Unicode whitespace and mixed ends" {
	expect_equal("\u{2003}é\u{2003}".trim(), "é")?
	expect_equal("é ".trim(), "é")?
	expect_equal(" é".trim(), "é")?
}

test "case mapping and normalization return text that needs no change" {
	expect_equal("abc".lower(), "abc")?
	expect_equal(pad(40).lower(), pad(40))?
	expect_equal("ABC".upper(), "ABC")?
	expect_equal(("A" + pad(40)).upper(), "A" + pad(40).upper())?
	expect_equal(("A" + pad(40)).lower(), "a" + pad(40))?
	expect_equal(("x" + pad(30) + "Z").upper(), "X" + pad(30).upper() + "Z")?
	expect_equal("a1 _-~".upper(), "A1 _-~")?
	expect_equal("@[`{".upper(), "@[`{")?
	expect_equal("@[`{".lower(), "@[`{")?
	expect_equal("É".lower(), "é")?
	expect_equal(pad(20).normalize("NFC", null).get_or(""), pad(20))?
	expect_equal("abc".normalize("NFKD", null).get_or(""), "abc")?
	expect_equal("e\u{301}".normalize("NFC", null).get_or(""), "é")?
	expect_true("abcdef".normalize("NFC", 3).is_error())?
	expect_equal("abc".normalize("NFC", 3).get_or(""), "abc")?
}
