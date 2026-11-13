// conform: tags=strings,testing,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn pad(n: Int) String:
	return "x".repeat(n).get("")

test "a short literal equals the same text built at run time":
	built := "ab{1}"
	expect_equal(built == "ab1", true)?
	expect_equal("ab1" == built, true)?
	expect_equal(built != "ab2", true)?
	expect_equal("abc" != "abcd", true)?
	expect_equal("abc" != "ab", true)?

test "a short literal differs from a long string and matches at the inline limit":
	expect_equal("abc" == pad(40), false)?
	expect_equal(pad(15) == "xxxxxxxxxxxxxxx", true)?
	expect_equal(pad(16) == "xxxxxxxxxxxxxxxx", true)?
	expect_equal(pad(16) == "xxxxxxxxxxxxxxx", false)?

test "a captured short literal is found in a list":
	needle := "k2"
	words := ["k1", "k2", "k3"]
	expect_equal(words.any(fn(w: String) Bool: w == needle), true)?
	expect_equal(words.find_index(fn(w: String) Bool: w == "k3").get(-1), 2)?
	expect_equal(words.contains("k1"), true)?
	expect_equal(words.contains("k4"), false)?
	expect_equal("héllo".length(), 5)?
