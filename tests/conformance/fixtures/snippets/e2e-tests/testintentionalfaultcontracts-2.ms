// conform: tags=closures,control-flow,faults,modules,stdlib-faults,stdlib-testing,testing,tier-stdlib,try-result
// conform: phase=test
// conform: origin=tests/e2e/intentional_faults_test.go:28 TestIntentionalFaultContracts
import (
	panic from "@std/core.ms",
	expect_contains, expect_fault from "@std/test/test.ms",
)

fn failed_initializer() Never:
	_impossible: Int := panic(message: "initializer cannot return")

fn returned_failure() Int:
	return panic(message: "result cannot return")

fn endless() Int:
	while true:
		continue

test "Never faults propagate through initializers and returned values":
	expect_contains(
		expect_fault(
			fn:
				_impossible := failed_initializer()
		)?,
		"initializer cannot return"
	)?
	expect_contains(
		expect_fault(
			fn:
				_impossible := returned_failure()
		)?,
		"result cannot return"
	)?
