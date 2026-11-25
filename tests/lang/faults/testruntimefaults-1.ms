// conform: tags=faults,formatter,optional,testing,tier-core
// conform: phase=test,parse
// conform: origin=tests/e2e/e2e_test.go:67 TestRuntimeFaults
import panic from "@std/core.ms"

test "fault" {
	missing Int? := null
	_impossible := missing or panic("called Optional.get() on null")
}
// expect-exit: 1
// expect-tests: passed=0 failed=1
