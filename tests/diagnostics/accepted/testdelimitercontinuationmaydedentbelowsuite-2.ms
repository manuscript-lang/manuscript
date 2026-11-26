// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/lexer/lexer_test.go:131 TestDelimiterContinuationMayDedentBelowSuite
fn f() Int {
	_x := (1 + 2)
	return 0
}
// expect-exit: 0
