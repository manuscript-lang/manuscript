// conform: tags=closures,formatter,modules,mutation,stdlib-testing,testing,tier-core,try-result
// conform: phase=test,parse
// conform: origin=tests/e2e/testdata/accept/closures-snapshot.ms
import expect_equal, expect_true from "@std/test/test.ms"

test "closures read the variable they borrow" {
	var offset = 3
	offset = 99

	first := () => {
		return offset
	}
	second := () => {
		return true
	}
	first() | expect_equal(99)?
	second() | expect_true?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
