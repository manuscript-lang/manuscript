// conform: tags=control-flow,faults,formatter,modules,stdlib-faults,testing,tier-stdlib
// conform: phase=test,parse
// conform: origin=tests/e2e/fault_locations_test.go:141 TestFaultSourceLocations
import panic from "@std/core.ms"

test "several checks" {
	good := 2 + 3
	if good == 5 {
		panic("last check failed")
	}
}
// expect-exit: 1
// expect-tests: passed=0 failed=1
