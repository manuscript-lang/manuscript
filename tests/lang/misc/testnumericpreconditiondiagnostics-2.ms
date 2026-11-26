// conform: tags=formatter,testing,tier-core
// conform: phase=test,parse
// conform: origin=tests/e2e/numeric_diagnostics_test.go:51 TestNumericPreconditionDiagnostics
test "continues after numeric faults" {
	_valid := 1
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
