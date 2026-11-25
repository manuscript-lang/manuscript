// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal, expect_false, expect_true from "@std/test/test.ms"

fn pad(n Int) String {
	return "x".repeat(n)
}

test "string order agrees across inline, static and heap forms" {
	expect_true("apple" < "banana")?
	expect_false("banana" < "apple")?
	expect_false("apple" < "apple")?
	expect_true("" < "a")?
	expect_false("a" < "")?
	expect_true("ab" < "abc")?
	expect_false("abc" < "ab")?
	expect_true("ab" < "ab\u{0}")?
	expect_true(pad(3) < pad(4))?
	expect_true(pad(16) < pad(17))?
	expect_true(pad(20) + "a" < pad(20) + "b")?
	expect_false(pad(20) + "b" < pad(20) + "a")?
	expect_true(pad(16) < pad(16) + "a")?
	expect_true("xa" < pad(40))?
	expect_false(pad(40) < "xa")?
	expect_true("é" > "z")?
	expect_equal(
		["pear", "fig", "apple", pad(18), "fi"].sorted(),
		["apple", "fi", "fig", "pear", pad(18)],
	)?
}

test "inline strings of up to fifteen bytes order by their words" {
	a := pad(9) + "b"
	expect_true(a < pad(9) + "c")?
	expect_false(pad(9) + "c" < a)?
	expect_true(pad(14) + "a" < pad(14) + "b")?
	expect_true(pad(14) < pad(15))?
	expect_false(pad(15) < pad(14))?
	expect_false(pad(15) < pad(15))?
	expect_true(pad(7) + "a" + pad(6) < pad(7) + "b")?
	expect_true(pad(8) + "é" > pad(8) + "z")?
	expect_true(pad(12) + "\u{1}" < pad(12) + "\u{2}" + "x")?
	expect_true(pad(12) + "\u{0}" < pad(12) + "\u{0}\u{0}")?
}
