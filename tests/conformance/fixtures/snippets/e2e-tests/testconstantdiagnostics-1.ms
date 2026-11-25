// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=tests/e2e/constants_test.go:12 TestConstantDiagnostics
fn f() Int {
	return 1
}

X := f()
// expect-error: MS3070 8:6 a constant takes literals, operators, collections, and other constants; compute this value in a function
