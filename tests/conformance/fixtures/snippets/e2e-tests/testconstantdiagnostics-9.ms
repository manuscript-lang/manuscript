// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=tests/e2e/constants_test.go:20 TestConstantDiagnostics
A Int := "x"
// expect-error: MS3001 4:10 expected Int, found String
