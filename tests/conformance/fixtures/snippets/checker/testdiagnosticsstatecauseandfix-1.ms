// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:20 TestDiagnosticsStateCauseAndFix
fn f(count Int) Int {
	return cuont
}
// expect-error: MS2001 5:12 unknown binding cuont; did you mean 'count'?
// expect-fix: 5:12-5:17 "count"
