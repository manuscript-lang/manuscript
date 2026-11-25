// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=tests/e2e/constants_test.go:13 TestConstantDiagnostics
fn f() Int {
	return 1
}

X := f
// expect-error: MS3000 8:6 a constant can refer only to other constants, but f is a function; compute the value in a function
