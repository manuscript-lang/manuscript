// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:60 TestDiagnosticsStateCauseAndFix
fn double(n Int) Int {
	return n * 2
}

fn f() Int {
	return [1, 2].map(double).length()
}
// expect-exit: 0
