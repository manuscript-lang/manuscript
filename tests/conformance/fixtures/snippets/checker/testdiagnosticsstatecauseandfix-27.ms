// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:46 TestDiagnosticsStateCauseAndFix
fn f() Int {
	s := null
	return 0
}
// expect-error: MS3080 5:10 cannot infer the type of null; give it a target, e.g. `x Int? := null`, or pass a value
