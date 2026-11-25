// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lexer/lexer_test.go:132 TestDelimiterContinuationMayDedentBelowSuite
fn f() Int {
	if true {
		_x := [1]
		return 0
	}

	return 1
}
// expect-exit: 0
