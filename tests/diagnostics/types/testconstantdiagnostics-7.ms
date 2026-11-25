// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/constants_test.go:18 TestConstantDiagnostics
A := 1

fn f() Int {
	return A()
}
// expect-error: MS3000 7:12 A is a constant, not a function; remove the parentheses and write A
