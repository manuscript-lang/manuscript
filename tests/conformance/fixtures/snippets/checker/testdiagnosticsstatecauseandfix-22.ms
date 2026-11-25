// conform: tags=diagnostics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:41 TestDiagnosticsStateCauseAndFix
fn f(n Int?) Int {
	return n
}
// expect-error: MS3001 5:12 expected Int, found Int? (in the return value); Int? may be absent; test it first with 'if x != null', or give a default with 'x or default'
