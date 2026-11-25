// conform: tags=diagnostics,formatter,sets,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:33 TestDiagnosticsStateCauseAndFix
fn f(values Set[Int]) Void {
	values.insert(1)
}
// expect-error: MS2001 5:12 unknown or ambiguous member insert on Set[Int]; did you mean 'add'?
// expect-fix: 5:12-5:18 "add"
