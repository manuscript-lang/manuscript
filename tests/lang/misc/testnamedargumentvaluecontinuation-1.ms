// conform: tags=formatter,testing,tier-core
// conform: phase=test,parse
// conform: origin=pkg/parser/parser_test.go:72 TestNamedArgumentValueContinuation
fn use(value Int) Void {
	return
}

test "continued argument" {
	use(value: 3)
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
