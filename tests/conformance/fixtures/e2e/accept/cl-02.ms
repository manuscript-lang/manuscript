// conform: tags=modules,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/cl-02.ms
import expect_equal, expect_false from "@std/test/test.ms"

fn invalid_division(zero: Int) Bool:
	return 1 / zero == 0

test "grouping and short circuit":
	expect_equal(2 + 3 * 4, 14)?
	expect_equal((2 + 3) * 4, 20)?
	expect_equal(10 - 3 - 2, 5)?
	expect_false(not (true or invalid_division(0)))?
	expect_false(not (not (false and invalid_division(0))))?
