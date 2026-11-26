// conform: tags=formatter,testing,tier-core
// conform: phase=test,parse
// conform: origin=pkg/frontend/source_test.go:74 TestProjectTestsDiscoverTestFiles
test "a" {
	return
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
