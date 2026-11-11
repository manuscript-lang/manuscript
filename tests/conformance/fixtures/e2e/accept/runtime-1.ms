// conform: tags=decimal,faults,modules,stdlib-decimal,stdlib-errors,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/runtime-1.ms
import (
	Decimal from "@std/math/decimal.ms",
	expect_equal from "@std/test/test.ms",
)

fn amount() Decimal!Error:
	return ok(12.50d)

test "explicit standard imports":
	expect_equal([1, 2].length(), 2)?
	expect_equal(amount().get(0.0d), 12.50d)?
