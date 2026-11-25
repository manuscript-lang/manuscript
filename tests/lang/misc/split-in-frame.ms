// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn describe(text String, sep String) String {
	f := text.split(sep)
	var out = f"{f.length()}:"
	for p in f { out += f"[{p}]" }
	return out
}

test "a split read in place matches the list the heap builds" {
	expect_equal(describe("a b c", " "), "3:[a][b][c]")?
	expect_equal(describe("", " "), "1:[]")?
	expect_equal(describe(" a  b ", " "), "5:[][a][][b][]")?
	expect_equal(describe("1 2 3 4 5 6 7 8", " "), "8:[1][2][3][4][5][6][7][8]")?
	expect_equal(
		describe("1 2 3 4 5 6 7 8 9 10", " "),
		"10:[1][2][3][4][5][6][7][8][9][10]",
	)?
	expect_equal(describe("héllo wörld ünï", " "), "3:[héllo][wörld][ünï]")?
	expect_equal(describe("aXXbXXc", "XX"), "3:[a][b][c]")?
	expect_equal(describe("abc", ""), "3:[a][b][c]")?
}

test "long texts" {
	long := "x ".repeat(100)
	expect_equal(long.split(" ").length(), 101)?

	wide := "abcdefghijklmnopqrstuvwxyz abcdefghijklmnopqrstuvwxyz"
	expect_equal(
		describe(wide, " "),
		"2:[abcdefghijklmnopqrstuvwxyz][abcdefghijklmnopqrstuvwxyz]",
	)?
}
