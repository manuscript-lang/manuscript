// conform: tags=formatter,modules,stdlib-bigint,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=test,parse
// conform: origin=tests/e2e/testdata/accept/library-bigint.ms
import (
	BigInt, parse_big_int from "@std/math/math.ms",
	expect_false from "@std/test/test.ms",
)

fn verify_bigint() Void! {
	large := parse_big_int(text: "18446744073709551616", radix: 10, max_digits: 30)?
	(
		(
			not (
				(
					(large).multiply(other: large)
				).to_string() == "340282366920938463463374607431768211456"
			)
		)
		| expect_false?
	)
}

test "large integers are exact" {
	verify_bigint()?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
