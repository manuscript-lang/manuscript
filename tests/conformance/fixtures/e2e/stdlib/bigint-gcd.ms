// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	from_int from "@std/math/math.ms",
	expect_equal from "@std/test/test.ms",
)

test "gcd and lcm retain magnitude across machine integer boundaries":
	one := from_int(1)
	zero := from_int(0)
	expect_equal(zero.gcd(zero), zero)?

	for bits in [32, 64]:
		boundary := from_int(2).pow(bits)?

		for divisor in [boundary - one, boundary.clone(), boundary + one]:
			dividend := divisor * from_int(2) + one
			expect_equal(dividend.gcd(divisor), one)?
			expect_equal(divisor.gcd(dividend), one)?

	for bits in [31, 32, 63, 64, 65, 127, 128, 2048]:
		consecutive := (from_int(2).pow(bits)?) + one
		factor := from_int(37)
		a := consecutive * factor
		b := (consecutive + one) * factor
		multiple := consecutive * (consecutive + one) * factor

		for left_sign in [-1, 1]:
			left := a * from_int(left_sign)
			expect_equal(left.gcd(zero), a)?
			expect_equal(zero.gcd(left), a)?
			expect_equal(left.gcd(left), a)?
			expect_equal(left.gcd(zero - left), a)?
			expect_equal(left.lcm(zero), zero)?

			for right_sign in [-1, 1]:
				right := b * from_int(right_sign)
				expect_equal(left.gcd(right), factor)?
				expect_equal(right.gcd(left), factor)?
				expect_equal(left.lcm(right), multiple)?
