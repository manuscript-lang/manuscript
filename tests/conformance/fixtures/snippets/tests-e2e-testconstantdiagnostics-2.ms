# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=tests/e2e/constants_test.go:13 TestConstantDiagnostics
def f() -> Int:
    return 1

let X = f
