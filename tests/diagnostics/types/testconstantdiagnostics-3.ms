// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/constants_test.go:14 TestConstantDiagnostics
A := B
B := A
// expect-error: MS3000 4:1 constant A depends on itself; break the cycle or compute the value in a function
