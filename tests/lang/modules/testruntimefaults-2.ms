// conform: tags=formatter,modules,stdlib-testing,testing,tier-core,try-result
// conform: phase=test,parse
// conform: origin=tests/e2e/e2e_test.go:68 TestRuntimeFaults
import expect_equal from "@std/test/test.ms"

test "failed assertion" {
	2 + 3 | expect_equal(expected: 6)?
}
