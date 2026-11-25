// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn first(text String, sep String) String {
	return text.split(sep)[0].clone()
}

test "the first piece of a split matches the list's first element" {
	line := "name18655 8457 x"
	expect_equal(line.split(" ")[0].clone(), "name18655")?
	expect_equal("".split(",")[0].clone(), "")?
	expect_equal(first("héllo wörld", " "), "héllo")?
	expect_equal(first("été", ""), "é")?
	expect_equal(first("abc", "xyz"), "abc")?
	expect_equal(first(",a", ","), "")?
}

test "the first piece can be kept after the text changes" {
	var text = "alpha beta"
	kept := text.split(" ")[0].clone()
	text = "gamma"
	expect_equal(kept, "alpha")?
	expect_equal(text, "gamma")?
}
