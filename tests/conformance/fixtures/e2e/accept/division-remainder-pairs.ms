// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn remainder_first(x: Int, y: Int) Int:
	r := x % y
	q := x / y
	return q * 1000 + r

fn quotient_first(x: Int, y: Int) Int:
	q := x / y
	r := x % y
	return q * 1000 + r

test "a quotient and a remainder of the same operands agree in either order":
	for y in [-1, 1, 3, -3, 7, -7]:
		for x in [-100, -7, -1, 0, 1, 7, 100]:
			remainder_first(x, y) | expect_equal(quotient_first(x, y))?
			remainder_first(x, y) | expect_equal(x / y * 1000 + x % y)?

test "a divisor of minus one gives the negated quotient and a zero remainder":
	quotient_first(-7, -1) | expect_equal(7000)?
	remainder_first(5, -1) | expect_equal(-5000)?
