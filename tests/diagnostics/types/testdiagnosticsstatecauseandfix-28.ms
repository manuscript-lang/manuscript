// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:47 TestDiagnosticsStateCauseAndFix
fn f() Int {
	x := 1
	return x()
}
// expect-error: MS3000 6:12 x is not a function (it has type Int); only functions and methods can be called, so remove the (...) or call a function instead
