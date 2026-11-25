// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:23 TestDiagnosticsStateCauseAndFix
fn f(x Strin) Void {
	return
}
// expect-error: MS2001 4:8 unknown type Strin; did you mean 'String'?
// expect-fix: 4:8-4:13 "String"
