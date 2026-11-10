// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=tests/e2e/constants_test.go:18 TestConstantDiagnostics
A := 1

fn f() Int:
    return A()
