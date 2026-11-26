// conform: tags=diagnostics,formatter,tier-core,try-result
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:40 TestDiagnosticsStateCauseAndFix
fn p() Int! {
	return ok(1)
}

fn f() Int {
	return p() + 1
}
// expect-error: MS3001 9:16 operator operands require the same independently known type, found Int! + Int; unwrap it with a trailing '?' inside a function that returns a compatible Result, with 'if value := x', or with '.get()'
