// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/diagnostic_fixes_test.go:28 TestDiagnosticFixes
fn helper() Int {
	return 1
}

fn f() Int {
	helper = 2
	return 0
}
// expect-error: MS3000 9:5 cannot assign to function helper; assignment targets are 'var' bindings and type fields
