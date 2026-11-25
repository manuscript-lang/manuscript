// conform: tags=faults,formatter,modules,stdlib-faults,testing,tier-stdlib
// conform: phase=test,parse
// conform: origin=internal/cli/project_check_test.go:53 TestProjectCheckDiscoveryAndReporting
import panic from "@std/core.ms"

test "never execute" {
	return panic("check executed code")
}
// expect-exit: 1
// expect-tests: passed=0 failed=1
