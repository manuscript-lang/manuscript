// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:43 TestDiagnosticsStateCauseAndFix
fn f() Int {
	return 3.5
}
// expect-error: MS3001 5:12 expected Int, found Float (in the return value); Float does not convert to Int implicitly; truncate_to_int() returns Int?, so unwrap it, e.g. value.truncate_to_int().get_or(0)
