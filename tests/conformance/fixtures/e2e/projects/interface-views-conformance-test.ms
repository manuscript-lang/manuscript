// conform: tags=diagnostics,modules,stdlib-testing,testing,tier-core,try-result
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/interface_views/conformance_test.ms
import (
	expect_equal from "@std/test/test.ms",

	invoke from "./domain.ms",
	left from "./left.ms",
	right from "./right.ms",
)

test "each module keeps its own view implementation":
	first := left()
	second := right()
	bound := first.read
	bound() | expect_equal(11)?
	second.read() | expect_equal(22)?
	invoke(first) | expect_equal(11)?
	invoke(second) | expect_equal(22)?
