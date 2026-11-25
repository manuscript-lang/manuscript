// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

test "a closure that only assigns a captured variable changes it" {
	var xs = ["a", "b"]
	var n = 0

	reset := () => {
		xs = ["c"]
		n = 7
	}

	reset()
	xs | expect_equal(["c"])?
	n | expect_equal(7)?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
