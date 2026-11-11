// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	Decimal from "@std/math/decimal.ms",
	expect_equal from "@std/test/test.ms",
)

test "decimal comparison orders signs exponent gaps and overlapping digits":
	ascending := [
		-1e6144d,
		-1e34d,
		-9999999999999999999999999999999999d,
		-1e33d,
		-1d,
		-1e-6176d,
		0d,
		1e-6176d,
		1d,
		9999999999999999999999999999999999d,
		1e34d,
		1e6144d,
	]

	for i in 0..ascending.length():
		expect_equal(ascending[i].compare(ascending[i]), 0)?

		for j in (i + 1)..ascending.length():
			expect_equal(ascending[i].compare(ascending[j]), -1)?
			expect_equal(ascending[j].compare(ascending[i]), 1)?

	expect_equal(1.1d.compare(1d), 1)?
	expect_equal((-1.1d).compare(-1d), -1)?
