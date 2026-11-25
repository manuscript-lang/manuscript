// conform: tags=diagnostics,formatter,sets,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:53 TestDiagnosticsStateCauseAndFix
fn f() Int {
	_s := Set[String]()
	return 0
}
// expect-exit: 0
