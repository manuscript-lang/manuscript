// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:25 TestDiagnosticsStateCauseAndFix
fn g(a Int) Int {
	return a
}

fn f() Int {
	return g()
}
// expect-error: MS3003 9:12 missing argument a: Int in call to g; add 'a: <Int>'
