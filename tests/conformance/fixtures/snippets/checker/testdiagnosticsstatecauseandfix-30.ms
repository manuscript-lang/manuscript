// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:49 TestDiagnosticsStateCauseAndFix
fn f() Int {
	x Int := 3.5
	y := x + 1
	return y
}
// expect-error: MS3001 5:14 expected Int, found Float (in the initializer of 'x'); Float does not convert to Int implicitly; truncate_to_int() returns Int?, so unwrap it, e.g. value.truncate_to_int().get_or(0)
