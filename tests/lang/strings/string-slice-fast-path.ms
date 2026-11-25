// conform: tags=strings,testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn grow(piece String, times Int) String {
	var s = ""
	var i = 0

	while i < times {
		s += piece
		i += 1
	}

	return s
}

test "short ascii pieces of an inline text" {
	s := "hello world"
	expect_equal(s.slice(0, 5), "hello")?
	expect_equal(s.slice(6, 11), "world")?
	expect_equal(s.slice(3, 3), "")?
	expect_equal(s.slice(0, 11), s)?
}

test "pieces of a flat text up to and beyond fifteen bytes" {
	s := grow("0123456789", 4)
	expect_equal(s.slice(0, 15), "012345678901234")?
	expect_equal(s.slice(5, 20), "567890123456789")?
	expect_equal(s.slice(0, 16), "0123456789012345")?
	expect_equal(s.slice(10, 40), "012345678901234567890123456789")?
	expect_equal(s.slice(0, 40), s)?
	expect_equal(s.slice(39, 40), "9")?
}

test "bounds outside the text, negative bounds and empty pieces" {
	s := grow("abc", 8)
	expect_equal(s.slice(20, 99), "cabc")?
	expect_equal("wxyz".slice(4, 9), "")?
	expect_equal(s.slice(-3, 24), "abc")?
	expect_equal(s.slice(2, 1), "")?
	expect_equal(s.slice(-100, 2), "ab")?
	expect_equal(s.slice(5, 500), s.slice(5, 24))?
}

test "bounds inside a scalar move inward" {
	s := "aé中b"
	expect_equal(s.slice(0, 2), "a")?
	expect_equal(s.slice(2, 4), "")?
	expect_equal(s.slice(1, 3), "é")?
	expect_equal(s.slice(1, 6), "é中")?

	t := grow("é", 12)
	expect_equal(t.slice(1, 5), "é")?
	expect_equal(t.slice(0, 16).length(), 16)?
}

test "a slice is its own copy" {
	var s = grow("xy", 10)
	piece := s.slice(2, 8)
	s += "!"
	expect_equal(piece, "xyxyxy")?
	expect_equal(s.slice(18, 21), "xy!")?
}
// expect-exit: 0
// expect-tests: passed=5 failed=0
