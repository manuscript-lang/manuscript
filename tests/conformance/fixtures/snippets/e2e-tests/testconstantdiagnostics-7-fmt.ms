// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/constants_test.go:18 TestConstantDiagnostics
A := 1

fn f() Int:
    return A()
