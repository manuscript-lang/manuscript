// conform: tags=control-flow,faults,modules,stdlib-faults,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/intentional_faults_test.go:12 TestIntentionalFaultContracts
import (
	panic from "@std/core.ms",
	expect_equal from "@std/test/test.ms",
)

fn positive(value: Int) Int:
	if value > 0:
		return value
	else:
		panic(message: "positive value required")

fn discard(value: Int) Unit:
	return

test "return contracts":
	positive(value: 3) | expect_equal(expected: 3)?
	discard(value: 1) | expect_equal(expected: unit)?
