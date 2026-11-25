// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/constants_test.go:16 TestConstantDiagnostics
A Int := B + 1
B Int := A + 1
// expect-error: MS3000 4:1 constant A depends on itself; break the cycle or compute the value in a function
