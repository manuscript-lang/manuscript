// conform: tags=ownership,tier-core
// conform: phase=test
import expect_equal from "@std/test/test.ms"

fn swapped() Int {
	var a = [1]
	var b = [1, 2]
	old := a
	a = b
	b = old
	return a.length() * 10 + b.length()
}

test "a binding of a var that is assigned afterwards owns the value" {
	expect_equal(swapped(), 21)?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
