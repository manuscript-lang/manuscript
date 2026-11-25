// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/constants_test.go:20 TestConstantDiagnostics
A Int := "x"
// expect-error: MS3001 4:10 expected Int, found String
