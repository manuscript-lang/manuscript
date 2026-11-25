// conform: tags=formatter,testing,tier-core
// conform: phase=test,parse
// conform: origin=internal/cli/project_check_test.go:54 TestProjectCheckDiscoveryAndReporting
test "valid" {
	_n := 1
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
