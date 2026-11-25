// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:56 TestDiagnosticsStateCauseAndFix
fn f() Int {
	return "abc".length()
}
// expect-exit: 0
