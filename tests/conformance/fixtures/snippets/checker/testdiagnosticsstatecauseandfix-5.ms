// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:24 TestDiagnosticsStateCauseAndFix
fn f() Int {
	x := 1
	x = 2
	return x
}
// expect-error: MS3060 6:5 cannot assign immutable binding x; declare it with 'var x = ...' instead of 'x := ...'
// expect-fix: 5:5-5:9 "var x ="
