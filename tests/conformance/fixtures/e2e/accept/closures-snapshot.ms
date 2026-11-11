// conform: tags=closures,modules,mutation,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/closures-snapshot.ms
import expect_equal, expect_true from "@std/test/test.ms"

test "closures read the variable they borrow":
	var offset = 3
	offset = 99

	first := fn:
		return offset
	second := fn:
		return true
	first() | expect_equal(99)?
	second() | expect_true?
