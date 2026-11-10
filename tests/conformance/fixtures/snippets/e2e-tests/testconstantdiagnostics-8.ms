// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=tests/e2e/constants_test.go:19 TestConstantDiagnostics
A := 1

fn f() Int:
    A = 2
    return A
