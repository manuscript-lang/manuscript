# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=tests/e2e/constants_test.go:18 TestConstantDiagnostics
let A = 1

def f() -> Int:
    return A()
