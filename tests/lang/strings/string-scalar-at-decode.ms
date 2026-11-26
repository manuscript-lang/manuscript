// conform: tags=testing,strings,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn walk(text String) List[Int] {
	var codes List[Int] = []
	var offset = 0

	while offset < text.length() {
		code := text.scalar_at(offset, -1)
		codes.append(code)
		offset += (
			if code < 128 { 1 } else { if code < 2048 { 2 } else { if code < 65536 { 3 } else { 4 } } }
		)
	}

	return codes
}

test "one to four byte scalars decode inline and on the heap" {
	expect_equal(walk("a\u{e9}\u{20ac}\u{1d11e}z"), [97, 233, 8364, 119070, 122])?

	long := "0123456789abcdef\u{e9}\u{20ac}\u{1d11e}\u{10ffff}"
	expect_equal(walk(long).length(), 20)?
	expect_equal(long.scalar_at(16, -1), 233)?
	expect_equal(long.scalar_at(18, -1), 8364)?
	expect_equal(long.scalar_at(21, -1), 119070)?
	expect_equal(long.scalar_at(25, -1), 1114111)?
}

test "an offset inside a scalar or outside the text gives the default" {
	text := "a\u{20ac}"
	expect_equal(text.scalar_at(2, -1), -1)?
	expect_equal(text.scalar_at(3, -1), -1)?
	expect_equal(text.scalar_at(4, -1), -1)?
	expect_equal(text.scalar_at(-1, -1), -1)?
}

test "a bound length is the byte length" {
	text := "h\u{e9}llo"
	size := text.length
	count := text.scalar_length
	expect_equal(size(), 6)?
	expect_equal(count(), 5)?
}
// expect-exit: 0
// expect-tests: passed=3 failed=0
