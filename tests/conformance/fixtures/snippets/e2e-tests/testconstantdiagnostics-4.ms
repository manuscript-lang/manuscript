// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=tests/e2e/constants_test.go:15 TestConstantDiagnostics
A := A + 1
// expect-error: MS3000 4:1 constant A depends on itself; break the cycle or compute the value in a function
