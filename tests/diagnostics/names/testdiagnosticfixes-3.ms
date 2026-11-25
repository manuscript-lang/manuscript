// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/diagnostic_fixes_test.go:23 TestDiagnosticFixes
fn f[Equal](a Equal) Void {
	return
}
// expect-error: MS2001 4:6 duplicate or intrinsic type parameter Equal; choose a different type parameter name
