// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:57 TestDiagnosticsStateCauseAndFix
fn f() Int {
	n := "abc".len()
	return 0
}
// expect-error: MS2001 5:16 unknown or ambiguous member len on String; did you mean 'length' or 'scalar_length'?
