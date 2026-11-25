// conform: tags=diagnostics,formatter,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/diagnostic_fixes_test.go:29 TestDiagnosticFixes
type Point {
	x Int
}

fn f() Int {
	Point = 2
	return 0
}
// expect-error: MS3000 9:5 cannot assign to type Point; assignment targets are 'var' bindings and type fields
