// conform: tags=diagnostics,formatter,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:59 TestDiagnosticsStateCauseAndFix
fn f() String {
	return [1.5].join(separator: ",")
}
// expect-exit: 0
