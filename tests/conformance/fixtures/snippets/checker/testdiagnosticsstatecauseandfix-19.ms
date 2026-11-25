// conform: tags=control-flow,diagnostics,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:38 TestDiagnosticsStateCauseAndFix
fn f(n Int?) Int {
	if n == 0 {
		return 1
	}
	return 0
}
// expect-exit: 0
