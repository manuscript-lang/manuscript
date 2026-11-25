// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/constants_test.go:19 TestConstantDiagnostics
A := 1

fn f() Int {
	A = 2
	return A
}
// expect-error: MS3000 7:5 cannot assign to constant A; assignment targets are 'var' bindings and type fields
