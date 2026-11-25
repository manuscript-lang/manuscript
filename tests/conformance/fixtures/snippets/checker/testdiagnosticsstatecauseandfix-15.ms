// conform: tags=diagnostics,lists,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:34 TestDiagnosticsStateCauseAndFix
fn f(values List[Int]) Void {
	values.delete(0)
}
// expect-error: MS2001 5:12 unknown or ambiguous member delete on List[Int]; did you mean 'remove'?
// expect-fix: 5:12-5:18 "remove"
